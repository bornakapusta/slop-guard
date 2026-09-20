# frozen_string_literal: true

module SlopGuard
  class Evaluator
    # The mutable outcome of one rule run. Outcome transitions: `not_applicable` → `no_concern` or `inconclusive`;
    # `concern` is terminal and a later gap does not downgrade it. `to_h` adds the `error` key only when a provider
    # or budget failure was recorded, matching the optional field in `docs/report-schema.md`.
    class RuleResult
      attr_reader :outcome, :findings, :gaps, :readings, :fingerprints, :error

      def self.skipped(reason)
        new.tap { |result| result.error!("Not attempted after an earlier provider failure: #{reason}") }
      end

      def initialize
        @outcome = 'not_applicable'
        @findings = []
        @gaps = []
        @readings = []
        @fingerprints = []
        @error = nil
      end

      def record(values, fingerprint)
        readings << values
        fingerprints << fingerprint
      end

      def concern!(finding)
        @outcome = 'concern'
        findings << finding
      end

      def no_concern!
        @outcome = 'no_concern' if outcome == 'not_applicable'
      end

      def inconclusive!(reason)
        gaps << reason
        @outcome = 'inconclusive' unless outcome == 'concern'
      end

      def error!(message)
        @error = message
        inconclusive!(message)
      end

      def to_h
        hash = { 'outcome' => outcome, 'findings' => findings.map(&:to_h), 'gaps' => gaps, 'readings' => readings,
                 'question_fingerprints' => fingerprints }
        hash['error'] = error if error
        hash
      end
    end
  end
end
