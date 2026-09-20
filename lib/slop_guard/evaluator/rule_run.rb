# frozen_string_literal: true

module SlopGuard
  class Evaluator
    # One rule applied to one snapshot. Subclasses implement `evaluate` for their rule kind; this base owns the
    # guard order, the single provider round trip per rule, and the outcome bookkeeping.
    # Instructions name scenarios and candidates by ID only; their text travels in the untrusted state.
    class RuleRun
      def self.for(rule, snapshot:, client:)
        (rule.tests? ? TestRuleRun : DesignRuleRun).new(rule: rule, snapshot: snapshot, client: client)
      end

      def initialize(rule:, snapshot:, client:)
        @rule = rule
        @snapshot = snapshot
        @client = client
        @result = RuleResult.new
      end

      # An empty diff with complete evidence is not applicable and asks nothing; incomplete evidence is
      # inconclusive and asks nothing. Provider and budget failures are recorded, never raised past here.
      def call
        return result.to_h if snapshot.changed.empty? && snapshot.gaps.empty?

        if snapshot.gaps.empty?
          evaluate
        else
          inconclusive(snapshot.gaps.join('; '))
        end
        result.to_h
      rescue ProviderError, LimitExceeded => e
        result.error!(e.message)
        result.to_h
      end

      private

      attr_reader :rule, :snapshot, :client, :result

      def evaluate
        raise NotImplementedError
      end

      # Every scenario or candidate of a rule is asked in one `ask`; the client splits it into requests. The
      # fingerprint covers exactly the state and typed questions handed to the client.
      def ask(questions)
        state = snapshot.state
        typed = questions.transform_values { |text| JevClient::Question.typed(text) }
        values = client.ask(state, typed)
        result.record(values, SlopGuard.digest([state, typed]))
        values
      end

      def high?(value)
        rule.high?(value)
      end

      def low?(value)
        rule.low?(value)
      end

      def concern(topic, anchor, readings, scenario: nil)
        return inconclusive('No validated source location for this concern') unless anchor

        result.concern!(Finding.new(id: Finding.id_for(rule: rule.id, topic: topic, scenario: scenario,
                                                       path: anchor['path']),
                                    rule: rule.id, severity: 'advisory', topic: topic,
                                    anchor: Anchor.new(path: anchor['path'], line: anchor['line'], side: 'head'),
                                    readings: readings, thresholds: rule.thresholds, message: rule.fetch('message'),
                                    correction: rule.fetch('correction'), scenario: scenario))
      end

      def no_concern
        result.no_concern!
      end

      def inconclusive(reason)
        result.inconclusive!(reason)
      end
    end
  end
end
