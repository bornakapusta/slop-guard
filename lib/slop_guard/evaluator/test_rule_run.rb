# frozen_string_literal: true

module SlopGuard
  class Evaluator
    # A `kind: tests` rule: for every enumerated scenario, does some test both exercise the production behaviour
    # and assert the promised result? Only this kind depends on the PR description's scenario sections.
    class TestRuleRun < RuleRun
      private

      def evaluate
        expectations = snapshot.expectations
        return inconclusive(expectations.gaps.join('; ')) unless expectations.gaps.empty?

        scenarios = expectations.public_send(rule.fetch('scenarios'))
        if scenarios.empty?
          applicable = ask('applicable' => rule.fetch('applicable'))['applicable']
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
                      "#{sid}/missing" => "#{context}. #{rule.fetch('missing')}" }
        tests.each do |test|
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
        return inconclusive("Unclear applicability or expectation: #{sid}") unless applicable?(reading)

        pairs = tests.map { |test| [reading.call("exercise_#{test['id']}"), reading.call("assert_#{test['id']}")] }
        covered = pairs.any? { |exercise, assertion| high?(exercise) && high?(assertion) }
        all_absent = pairs.all? { |exercise, assertion| low?(exercise) || low?(assertion) }
        if high?(reading.call('missing')) && all_absent
          concern(sid, snapshot.anchor(scenario: scenario['text']), own_readings(sid, values),
                  scenario: scenario['text'])
        elsif low?(reading.call('missing')) && covered
          no_concern
        else
          inconclusive("Conflicting or uncertain coverage evidence: #{sid}")
        end
      end

      def applicable?(reading)
        high?(reading.call('applicable')) && high?(reading.call('clear'))
      end

      # The scenario's own readings, keyed without the scenario prefix, as recorded on the finding.
      def own_readings(sid, values)
        prefix = "#{sid}/"
        values.filter_map { |key, value| [key.delete_prefix(prefix), value] if key.start_with?(prefix) }.to_h
      end

      def tests
        snapshot.candidates.tests
      end
    end
  end
end
