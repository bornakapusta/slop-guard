# frozen_string_literal: true

module SlopGuard
  class Evaluator
    # A `kind: design` rule: a whole-context judgment gates per-candidate questions, and a concern needs both to
    # agree on a changed candidate that locates it.
    class DesignRuleRun < RuleRun
      private

      def evaluate
        global = ask('applicable' => rule.fetch('applicable'), 'concern' => rule.fetch('global'))
        return if low?(global['applicable'])
        return inconclusive('Design rule applicability is uncertain') unless high?(global['applicable'])

        candidates = snapshot.changed_candidates(rule.fetch('candidate_kind'))
        return inconclusive('No supported changed candidate locates the design judgment') if candidates.empty?

        values = ask(candidate_questions(candidates))
        candidates.each do |candidate|
          own = rule.fetch('candidate').keys.to_h { |key| [key, values.fetch("#{candidate['id']}/#{key}")] }
          classify_candidate(candidate, own, global)
        end
        return unless high?(global['concern']) && result.findings.empty?

        inconclusive('Whole-context concern has no supported local evidence')
      end

      def candidate_questions(candidates)
        candidates.each_with_object({}) do |candidate, all|
          reference = "Candidate #{candidate['id']} (see candidates in the supplied state)."
          rule.fetch('candidate').each { |key, text| all["#{candidate['id']}/#{key}"] = "#{reference} #{text}" }
        end
      end

      def classify_candidate(candidate, values, global)
        verdict = classify_design(values)
        if high?(global['concern']) && verdict == :present
          concern(candidate['name'], snapshot.anchor(candidate), values.merge('global' => global['concern']))
        elsif low?(global['concern']) && verdict == :ruled_out
          no_concern
        elsif high?(global['concern']) && verdict == :ruled_out
          # Another candidate may explain the global concern; `evaluate` reconciles after the loop.
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
        alternatives = rule.fetch('any_positive', [])
        positives_high = rule.fetch('positive').all? { |key| high?(values.fetch(key)) } &&
                         (alternatives.empty? || alternatives.any? { |key| high?(values.fetch(key)) })
        negatives_low = rule.fetch('negative').all? { |key| low?(values.fetch(key)) }
        any_negative_high = rule.fetch('negative').any? { |key| high?(values.fetch(key)) }
        any_positive_low = rule.fetch('positive').any? { |key| low?(values.fetch(key)) } ||
                           (!alternatives.empty? && alternatives.all? { |key| low?(values.fetch(key)) })
        if positives_high && negatives_low
          :present
        elsif any_negative_high || any_positive_low
          :ruled_out
        else
          :uncertain
        end
      end
    end
  end
end
