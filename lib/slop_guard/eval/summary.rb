# frozen_string_literal: true

module SlopGuard
  # Presents completed and interrupted CI evaluations without inventing qualification.
  class EvaluationSummary
    attr_reader :report, :expected, :reserved, :exit_status

    def initialize(report:, case_ids:, reserved:, exit_status:)
      @report = report
      @expected = case_ids.product([1, 2, 3])
      @reserved = reserved
      @exit_status = exit_status
      validate!
    end

    def status
      return 'INCOMPLETE' unless complete?
      return 'FAILED' unless exit_status.zero? && report.fetch('passed') &&
                             runs.all? { |run| run.fetch('score').fetch('passed') } &&
                             runs.none? { |run| run.fetch('report').fetch('status') == 'failed' } && clean_metrics?

      'PASSED DEVELOPMENT LABELS'
    end

    def markdown
      lines = ['## Jev development evaluation', '', "Status: **#{status}**",
               "Completed case/repeat pairs: #{runs.size}/#{expected.size}.",
               "Evaluator exit status: #{exit_status}.",
               "Labels reviewed: #{report.fetch('labels_reviewed')}.",
               "Reported tokens from completed cases: #{runs.sum { |run| run.fetch('input_tokens') }}.",
               format('Estimated input cost for completed cases: $%.6f.', estimated_cost),
               format('Reserved budget from the request ledger: $%.6f (not actual charges).', reserved), '']
      if complete?
        lines << '| Rule | Detected | False positives | Misses | Unnecessary abstentions |'
        lines << '|---|---:|---:|---:|---:|'
        report.fetch('metrics').fetch('by_rule').each do |id, counts|
          values = counts.values_at('true_positives', 'false_positives', 'misses', 'unnecessary_abstentions')
          lines << "| #{Report.escape(id)} | #{values.join(' | ')} |"
        end
        lines << "Cases with outcome changes across repeats: #{report.fetch('metrics').fetch('outcome_flips')}."
      else
        lines << 'This run is incomplete. Final metrics and repeat stability are unavailable.'
      end
      if report.key?('case_ids')
        analysis = EvaluationAnalysis.new(report, case_ids: expected.map(&:first).uniq)
        lines << '' << analysis.markdown
      end
      lines << '' << '### Recorded versions'
      report.fetch('versions').each { |name, value| lines << "- #{Report.escape(name)}: #{Report.escape(value)}" }
      lines << '' << 'Development results are separate from code-quality CI and held-out qualification.'
      lines << 'Provisional labels do not establish agreed review quality.' unless report.fetch('labels_reviewed')
      lines.join("\n")
    end

    private

    def runs
      report.fetch('runs')
    end

    def estimated_cost
      runs.sum { |run| run.fetch('estimated_usd') }
    end

    def clean_metrics?
      report.fetch('metrics').fetch('by_rule').values.all? do |counts|
        counts.values_at('false_positives', 'misses', 'unnecessary_abstentions').all?(&:zero?)
      end
    end

    def complete?
      pairs = runs.map { |run| run.values_at('case', 'repeat') }
      pairs.sort == expected.sort && report['metrics'].is_a?(Hash) && report['seconds'].is_a?(Numeric)
    end

    def validate!
      unless report.is_a?(Hash) && report['live'] == true && report['split'] == 'development' &&
             report['repetitions'] == 3 && report['runs'].is_a?(Array) && !expected.empty? &&
             expected.uniq == expected && report['versions'].is_a?(Hash) &&
             [true, false].include?(report['passed']) && [true, false].include?(report['labels_reviewed'])
        raise InvalidInput, 'Invalid development evaluation report'
      end

      pairs = runs.map { |run| run.values_at('case', 'repeat') }
      unless pairs.uniq == pairs && (pairs - expected).empty?
        raise InvalidInput,
              'Duplicate or unexpected case/repeat pair'
      end
      raise InvalidInput, 'Invalid reservation total' unless nonnegative?(reserved)

      runs.each do |run|
        unless [true, false].include?(run.fetch('score').fetch('passed')) &&
               %w[complete incomplete failed].include?(run.fetch('report').fetch('status'))
          raise InvalidInput, 'Invalid completed case result'
        end

        %w[input_tokens estimated_usd].each do |key|
          raise InvalidInput, 'Invalid case usage' unless nonnegative?(run.fetch(key))
        end
      end
      raise InvalidInput, 'Invalid evaluation duration' if report.key?('seconds') && !nonnegative?(report['seconds'])
      return unless report['metrics']

      validate_metrics!(report.fetch('metrics'))
    rescue KeyError, TypeError
      raise InvalidInput, 'Malformed development evaluation report'
    end

    def validate_metrics!(metrics)
      raise InvalidInput, 'Invalid finalized metrics' unless metrics.fetch('by_rule').keys.sort == Rules::IDS

      metrics.fetch('by_rule').each_value do |counts|
        %w[true_positives false_positives misses unnecessary_abstentions].each do |key|
          value = counts.fetch(key)
          raise InvalidInput, 'Invalid finalized counts' unless value.is_a?(Integer) && value >= 0
        end
      end
      flips = metrics.fetch('outcome_flips')
      raise InvalidInput, 'Invalid repeat count' unless flips.is_a?(Integer) && flips >= 0
    end

    def nonnegative?(value)
      value.is_a?(Numeric) && value.finite? && value >= 0
    end
  end
end
