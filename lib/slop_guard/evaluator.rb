# frozen_string_literal: true

module SlopGuard
  # Reconciles typed readings with rule thresholds and validated source anchors.
  class Evaluator
    attr_reader :client, :rules

    def initialize(client:, rules: Rules.new)
      @client = client
      @rules = rules
    end

    def call(snapshot)
      @snapshot = snapshot
      @results = {}
      rules.definitions.each do |id, rule|
        @id = id
        @rule = rule
        @result = { 'outcome' => 'not_applicable', 'findings' => [], 'gaps' => [], 'readings' => [] }
        @results[id] = @result
        next if snapshot.changed.empty?

        unless snapshot.gaps.empty?
          inconclusive(snapshot.gaps.join('; '))
          next
        end
        begin
          %w[G1 G2].include?(id) ? evaluate_tests : evaluate_design
        rescue ProviderError, LimitExceeded => e
          @result['error'] = e.message
          inconclusive(e.message)
        end
      end
      errors = @results.values.any? { |value| value['error'] }
      gaps = @results.values.any? { |value| !value['gaps'].empty? }
      status = if errors
                 'failed'
               else
                 (gaps ? 'incomplete' : 'complete')
               end
      { 'snapshot' => snapshot.identity, 'version' => VERSION, 'model' => JevClient::MODEL,
        'rules_revision' => rules.revision, 'status' => status,
        'rules' => @results, 'skipped_paths' => snapshot.skipped }
    end

    private

    def ask(questions)
      values = client.ask(@snapshot.state, questions.transform_values { |text| rules.question(text) })
      @result['readings'] << values
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
      scenarios = @id == 'G1' ? expectations.behaviors : expectations.failures
      if scenarios.empty?
        applicable = ask('applicable' => @rule.fetch('applicable'))['applicable']
        inconclusive('Relevant failure scenarios are not explicitly enumerated') unless low?(applicable)
        return
      end
      scenarios.each do |scenario|
        context = "Scenario #{scenario.fetch('id')}: #{scenario.fetch('text')}"
        questions = { 'clear' => "#{context}. Is this a single unambiguous requirement " \
                                 "consistent with the PR's stated purpose?",
                      'applicable' => "#{context}. Is this scenario relevant to behavior changed by the PR?",
                      'missing' => "#{context}. #{@rule.fetch('missing')}" }
        @snapshot.candidates.tests.each do |test|
          reference = "Test candidate #{test['id']} in #{test['path']}:#{test['line']}, " \
                      "including surrounding setup. #{context}."
          questions["exercise_#{test['id']}"] =
            "#{reference} Does this test exercise the relevant production behavior " \
            'rather than replacing that behavior with a stub?'
          questions["assert_#{test['id']}"] = "#{reference} Does this test assert the scenario's promised result?"
        end
        values = ask(questions)
        if low?(values['applicable'])
          next
        elsif !high?(values['applicable']) || !high?(values['clear'])
          inconclusive("Unclear applicability or expectation: #{scenario['id']}")
          next
        end

        pairs = @snapshot.candidates.tests.map do |test|
          [values["exercise_#{test['id']}"], values["assert_#{test['id']}"]]
        end
        covered = pairs.any? { |exercise, assertion| high?(exercise) && high?(assertion) }
        all_absent = pairs.all? { |exercise, assertion| low?(exercise) || low?(assertion) }
        if high?(values['missing']) && all_absent
          concern(scenario['id'], @snapshot.anchor, values, scenario: scenario['text'])
        elsif low?(values['missing']) && covered
          no_concern
        else
          inconclusive("Conflicting or uncertain coverage evidence: #{scenario['id']}")
        end
      end
    end

    def evaluate_design
      global = ask('applicable' => @rule.fetch('applicable'), 'concern' => @rule.fetch('global'))
      return if low?(global['applicable'])

      unless high?(global['applicable'])
        inconclusive('Design rule applicability is uncertain')
        return
      end
      kind = @id == 'G3' ? 'method' : 'class'
      candidates = @snapshot.changed_candidates(kind)
      if candidates.empty?
        inconclusive('No supported changed candidate locates the design judgment')
        return
      end
      candidates.each do |candidate|
        ref = "Candidate #{candidate['id']}: #{candidate['name']} at #{candidate['path']}:#{candidate['line']}."
        questions = @rule.fetch('candidate').transform_values { |text| "#{ref} #{text}" }
        values = ask(questions)
        yes = @rule.fetch('positive').all? { |key| high?(values.fetch(key)) }
        alternatives = @rule.fetch('any_positive', [])
        yes &&= alternatives.empty? || alternatives.any? { |key| high?(values.fetch(key)) }
        no = @rule.fetch('negative').all? { |key| low?(values.fetch(key)) }
        exempt = @rule.fetch('negative').any? { |key| high?(values.fetch(key)) }
        absent = @rule.fetch('positive').any? { |key| low?(values.fetch(key)) }
        absent ||= !alternatives.empty? && alternatives.all? { |key| low?(values.fetch(key)) }
        if high?(global['concern']) && yes && no
          concern(candidate['name'], @snapshot.anchor(candidate), values.merge('global' => global['concern']))
        elsif low?(global['concern']) && (exempt || absent)
          no_concern
        elsif high?(global['concern']) && (exempt || absent)
          # Another candidate may explain the global concern; reconcile after the loop.
          next
        else
          inconclusive("Conflicting or uncertain design evidence: #{candidate['name']}")
        end
      end
      return unless high?(global['concern']) && @result['findings'].empty?

      inconclusive('Whole-context concern has no supported local evidence')
    end

    def concern(topic, anchor, readings, scenario: nil)
      unless anchor
        inconclusive('No validated source location for this concern')
        return
      end
      @result['outcome'] = 'concern'
      @result['findings'] << { 'rule' => @id, 'topic' => topic, 'anchor' => anchor, 'readings' => readings,
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
