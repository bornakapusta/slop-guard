# frozen_string_literal: true

module SlopGuard
  # Reconciles typed readings with rule thresholds and validated source anchors.
  class Evaluator
    REPORT_VERSION = 1

    attr_reader :client, :rules

    def initialize(client:, rules: Rules.new)
      @client = client
      @rules = rules
    end

    # Safe to call repeatedly and concurrently: every review keeps its state in its own RuleRun objects.
    # After a provider or budget failure the remaining rules are not attempted: they would spend reservations on a
    # provider that just failed, and the review is already `failed`.
    def call(snapshot)
      failure = nil
      results = rules.definitions.to_h do |id, rule|
        if failure
          [id, RuleRun.skipped(failure)]
        else
          result = RuleRun.new(id: id, rule: rule, snapshot: snapshot, rules: rules, client: client).call
          failure = result['error']
          [id, result]
        end
      end
      errors = results.values.any? { |value| value['error'] }
      gaps = results.values.any? { |value| !value['gaps'].empty? }
      status = if errors
                 'failed'
               elsif gaps
                 'incomplete'
               else
                 'complete'
               end
      { 'report_version' => REPORT_VERSION, 'snapshot' => snapshot.identity, 'version' => VERSION,
        'model' => client.model, 'rules_revision' => rules.revision, 'status' => status,
        'rules' => results, 'skipped_paths' => snapshot.skipped, 'source' => snapshot.source }
    end

    # One rule applied to one snapshot. Holds the per-rule result so Evaluator itself stays stateless.
    # Every scenario or candidate of a rule is asked in one `ask`; the client splits it into requests.
    # Instructions name scenarios and candidates by ID only; their text travels in the untrusted state.
    class RuleRun
      def self.skipped(reason)
        message = "Not attempted after an earlier provider failure: #{reason}"
        { 'outcome' => 'inconclusive', 'findings' => [], 'gaps' => [message], 'readings' => [],
          'question_fingerprints' => [], 'error' => message }
      end

      def initialize(id:, rule:, snapshot:, rules:, client:)
        @id = id
        @rule = rule
        @snapshot = snapshot
        @rules = rules
        @client = client
        @result = { 'outcome' => 'not_applicable', 'findings' => [], 'gaps' => [], 'readings' => [],
                    'question_fingerprints' => [] }
      end

      def call
        return @result if @snapshot.changed.empty? && @snapshot.gaps.empty?

        if @snapshot.gaps.empty?
          @rules.test_rule?(@id) ? evaluate_tests : evaluate_design
        else
          inconclusive(@snapshot.gaps.join('; '))
        end
        @result
      rescue ProviderError, LimitExceeded => e
        @result['error'] = e.message
        inconclusive(e.message)
        @result
      end

      private

      def ask(questions)
        state = @snapshot.state
        typed = questions.transform_values { |text| @rules.question(text) }
        values = @client.ask(state, typed)
        @result['readings'] << values
        @result['question_fingerprints'] << SlopGuard.digest([state, typed])
        values
      end

      def high?(value)
        value >= @rule.fetch('high')
      end

      def low?(value)
        value <= @rule.fetch('low')
      end

      def evaluate_tests
        expectations = @snapshot.expectations
        unless expectations.gaps.empty?
          inconclusive(expectations.gaps.join('; '))
          return
        end
        scenarios = expectations.public_send(@rule.fetch('scenarios'))
        if scenarios.empty?
          applicable = ask('applicable' => @rule.fetch('applicable'))['applicable']
          inconclusive('Relevant failure scenarios are not explicitly enumerated') unless low?(applicable)
          return
        end
        values = ask(scenarios.each_with_object({}) { |scenario, all| all.merge!(scenario_questions(scenario)) })
        scenarios.each { |scenario| classify_scenario(scenario, values) }
      end

      def scenario_questions(scenario)
        sid = scenario.fetch('id')
        context = "Scenario #{sid} (see scenarios in the supplied state)"
        questions = { "#{sid}/clear" => "#{context}. Is this a single unambiguous requirement " \
                                        "consistent with the PR's stated purpose?",
                      "#{sid}/applicable" => "#{context}. Is this scenario relevant to behavior changed by the PR?",
                      "#{sid}/missing" => "#{context}. #{@rule.fetch('missing')}" }
        @snapshot.candidates.tests.each do |test|
          reference = "Test candidate #{test['id']} (see candidates in the supplied state), " \
                      "including surrounding setup. #{context}."
          questions["#{sid}/exercise_#{test['id']}"] =
            "#{reference} Does this test exercise the relevant production behavior " \
            'rather than replacing that behavior with a stub?'
          questions["#{sid}/assert_#{test['id']}"] =
            "#{reference} Does this test assert the scenario's promised result?"
        end
        questions
      end

      def classify_scenario(scenario, values)
        sid = scenario.fetch('id')
        reading = ->(key) { values.fetch("#{sid}/#{key}") }
        return if low?(reading.call('applicable'))

        unless high?(reading.call('applicable')) && high?(reading.call('clear'))
          inconclusive("Unclear applicability or expectation: #{sid}")
          return
        end

        pairs = @snapshot.candidates.tests.map do |test|
          [reading.call("exercise_#{test['id']}"), reading.call("assert_#{test['id']}")]
        end
        covered = pairs.any? { |exercise, assertion| high?(exercise) && high?(assertion) }
        all_absent = pairs.all? { |exercise, assertion| low?(exercise) || low?(assertion) }
        prefix = "#{sid}/"
        own = values.filter_map { |key, value| [key.delete_prefix(prefix), value] if key.start_with?(prefix) }.to_h
        if high?(reading.call('missing')) && all_absent
          concern(sid, @snapshot.anchor(scenario: scenario['text']), own, scenario: scenario['text'])
        elsif low?(reading.call('missing')) && covered
          no_concern
        else
          inconclusive("Conflicting or uncertain coverage evidence: #{sid}")
        end
      end

      def evaluate_design
        global = ask('applicable' => @rule.fetch('applicable'), 'concern' => @rule.fetch('global'))
        return if low?(global['applicable'])

        unless high?(global['applicable'])
          inconclusive('Design rule applicability is uncertain')
          return
        end
        candidates = @snapshot.changed_candidates(@rule.fetch('candidate_kind'))
        if candidates.empty?
          inconclusive('No supported changed candidate locates the design judgment')
          return
        end
        questions = candidates.each_with_object({}) do |candidate, all|
          reference = "Candidate #{candidate['id']} (see candidates in the supplied state)."
          @rule.fetch('candidate').each { |key, text| all["#{candidate['id']}/#{key}"] = "#{reference} #{text}" }
        end
        values = ask(questions)
        candidates.each do |candidate|
          own = @rule.fetch('candidate').keys.to_h { |key| [key, values.fetch("#{candidate['id']}/#{key}")] }
          classify_candidate(candidate, own, global)
        end
        return unless high?(global['concern']) && @result['findings'].empty?

        inconclusive('Whole-context concern has no supported local evidence')
      end

      def classify_candidate(candidate, values, global)
        verdict = classify_design(values)
        if high?(global['concern']) && verdict == :present
          concern(candidate['name'], @snapshot.anchor(candidate), values.merge('global' => global['concern']))
        elsif low?(global['concern']) && verdict == :ruled_out
          no_concern
        elsif high?(global['concern']) && verdict == :ruled_out
          # Another candidate may explain the global concern; evaluate_design reconciles after the loop.
          nil
        else
          inconclusive("Conflicting or uncertain design evidence: #{candidate['name']}")
        end
      end

      # :present when every positive question is high and every negative low; :ruled_out when a negative is high
      # or a positive is low; :uncertain otherwise.
      def classify_design(values)
        # `any_positive` is used only by the saved sample-project G3 definition (config/rules/g3.yml); it stays so the
        # benchmark rule revision is preserved. Do not generalise it further without evaluation evidence.
        alternatives = @rule.fetch('any_positive', [])
        positives_high = @rule.fetch('positive').all? { |key| high?(values.fetch(key)) } &&
                         (alternatives.empty? || alternatives.any? { |key| high?(values.fetch(key)) })
        negatives_low = @rule.fetch('negative').all? { |key| low?(values.fetch(key)) }
        any_negative_high = @rule.fetch('negative').any? { |key| high?(values.fetch(key)) }
        any_positive_low = @rule.fetch('positive').any? { |key| low?(values.fetch(key)) } ||
                           (!alternatives.empty? && alternatives.all? { |key| low?(values.fetch(key)) })
        if positives_high && negatives_low
          :present
        elsif any_negative_high || any_positive_low
          :ruled_out
        else
          :uncertain
        end
      end

      def concern(topic, anchor, readings, scenario: nil)
        unless anchor
          inconclusive('No validated source location for this concern')
          return
        end
        @result['outcome'] = 'concern'
        # The id is stable across repeats and readings, so publishers can update rather than duplicate comments.
        id = SlopGuard.digest('rule' => @id, 'topic' => topic, 'scenario' => scenario, 'path' => anchor['path'])
        @result['findings'] << { 'id' => id, 'rule' => @id, 'severity' => 'advisory', 'topic' => topic,
                                 'anchor' => anchor.merge('side' => 'head'), 'readings' => readings,
                                 'thresholds' => @rule.slice('high', 'low'), 'message' => @rule.fetch('message'),
                                 'correction' => @rule.fetch('correction'), 'scenario' => scenario }
      end

      def no_concern
        @result['outcome'] = 'no_concern' if @result['outcome'] == 'not_applicable'
      end

      def inconclusive(reason)
        @result['gaps'] << reason
        @result['outcome'] = 'inconclusive' unless @result['outcome'] == 'concern'
      end
    end
  end
end
