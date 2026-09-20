# frozen_string_literal: true

module SlopGuard
  # Measures agreement and repeatability separately on fixed saved review inputs.
  class EvaluationAnalysis
    OUTCOMES = %w[concern no_concern not_applicable inconclusive].freeze
    RULES = %w[G1 G2 G3 G4].freeze
    COUNTS = %w[true_positives false_positives misses correct_abstentions unnecessary_abstentions].freeze

    def initialize(report, case_ids:)
      raise InvalidInput, 'Malformed evaluation report' unless report.is_a?(Hash) && report['runs'].is_a?(Array)

      @report = report
      @case_ids = case_ids
      @runs = report.fetch('runs')
      validate!
    rescue KeyError, TypeError
      raise InvalidInput, 'Malformed evaluation report'
    end

    def to_h
      valid = @runs.reject { |run| run.fetch('report').fetch('status') == 'failed' }
      expected = @case_ids.size * @report.fetch('repetitions')
      complete = @runs.size == expected && @report.key?('metrics') && @report.key?('seconds') &&
                 @report['completed'] != false
      { 'analysis_version' => 1, 'source_report_digest' => SlopGuard.digest(@report),
        'live' => @report.fetch('live'), 'labels_reviewed' => @report.fetch('labels_reviewed'),
        'versions' => @report.fetch('versions'), 'split' => @report.fetch('split'),
        'complete' => complete, 'distinct_cases' => @case_ids.size,
        'observed_cases' => @runs.map { |run| run.fetch('case') }.uniq.size,
        'repetitions' => @report.fetch('repetitions'), 'expected_reviews' => expected,
        'observed_reviews' => @runs.size, 'operational_failures' => @runs.size - valid.size,
        'exact_matches' => valid.count { |run| run.fetch('score').fetch('passed') },
        'exact_match_rate_observed' => ratio(valid.count { |run| run.fetch('score').fetch('passed') }, @runs.size),
        'by_rule' => RULES.to_h { |id| [id, rule_metrics(id, valid)] },
        'per_case' => @case_ids.to_h { |id| [id, case_metrics(id, valid)] },
        'review_latency_seconds' => distribution(@runs.filter_map { |run| run['review_seconds'] }),
        'usage' => usage,
        'probability_variance' => probability_variance(valid) }
    end

    # The compact totals the runner stores as `metrics` and the CI summary reads. One definition for every count.
    def metrics
      valid = @runs.reject { |run| run.fetch('report').fetch('status') == 'failed' }
      totals = COUNTS.to_h { |key| [key, valid.sum { |run| run.fetch('score').fetch(key) }] }
      totals.merge(rates(totals),
                   'operational_failures' => @runs.size - valid.size,
                   'outcome_flips' => @runs.group_by { |run| run.fetch('case') }.count do |_, runs|
                     runs.map { |run| run.fetch('score').fetch('actual_outcomes') }.uniq.size > 1
                   end,
                   'by_rule' => RULES.to_h { |id| [id, rule_counts(id, valid)] })
    end

    def markdown
      data = to_h
      lines = ['# Slop Guard evaluation benchmark', '',
               "Evidence: #{data['live'] ? 'live provider responses' : 'offline/synthetic responses'}.",
               "Inventory: #{data['complete'] ? 'complete' : 'PARTIAL'}; " \
               "#{data['observed_reviews']}/#{data['expected_reviews']} reviews, " \
               "#{data['observed_cases']}/#{data['distinct_cases']} distinct cases, " \
               "#{data['repetitions']} requested repetitions.",
               "Labels: #{data['labels_reviewed'] ? 'marked reviewed in the source report' : 'PROVISIONAL'}.",
               "Operational failures: #{data['operational_failures']}.",
               "Exact matches among observed reviews: #{data['exact_matches']}/#{data['observed_reviews']}.", '',
               '| Rule | Outcome matches / valid reviews | Outcome agreement | Repeat agreement | Detected concerns |',
               '|---|---:|---:|---:|---:|']
      data['by_rule'].each do |id, metric|
        lines << "| #{id} | #{metric['matches']}/#{metric['observations']} | #{percent(metric['accuracy'])} | " \
                 "#{percent(metric['mean_case_repeat_agreement'])} | " \
                 "#{metric['true_positives']}/#{metric['true_positives'] + metric['misses']} |"
      end
      latency = data.fetch('review_latency_seconds')
      lines += ['', "Review latency: #{latency['samples']} measured; mean #{number(latency['mean'])} s, " \
                    "p50 #{number(latency['p50'])} s, p95 #{number(latency['p95'])} s.",
                format('Input cost estimate: $%<cost>.6f; reservations in observed reviews: $%<reserved>.6f.',
                       cost: data['usage']['estimated_usd'], reserved: data['usage']['reserved_usd']),
                'Rule agreement excludes operational failures; exact matches include failed reviews as mismatches.',
                'Repeat agreement averages within-case pairs. Stable answers can still be wrong.',
                'Detected concerns match rule, reason and anchor; inspect misses and false positives.',
                'JSON includes confusion counts, per-case results and conditional per-question sample variance.',
                'Review latency includes all provider requests. Cost estimates are not actual charges.',
                'Partial results describe only observed reviews. Repetitions do not add independent cases.',
                'This report does not establish held-out qualification or human approval of provisional labels.']
      lines.join("\n")
    end

    private

    def rule_metrics(id, valid)
      confusion = OUTCOMES.to_h { |expected| [expected, OUTCOMES.to_h { |actual| [actual, 0] }] }
      valid.each do |run|
        score = run.fetch('score')
        confusion[score.fetch('expected_outcomes').fetch(id)][score.fetch('actual_outcomes').fetch(id)] += 1
      end
      matches = OUTCOMES.sum { |outcome| confusion[outcome][outcome] }
      agreements = valid.group_by { |run| run.fetch('case') }.values.filter_map do |runs|
        pair_agreement(runs.map { |run| run.fetch('score').fetch('actual_outcomes').fetch(id) })
      end
      counts = rule_counts(id, valid)
      counts.merge('matches' => matches, 'observations' => valid.size, 'accuracy' => ratio(matches, valid.size),
                   'confusion_expected_actual' => confusion, 'cases_with_pairs' => agreements.size,
                   'mean_case_repeat_agreement' => mean(agreements),
                   'finding_precision' => counts.fetch('precision'), 'finding_recall' => counts.fetch('recall'))
    end

    # Abstention counts are absent from the oldest saved reports and default to zero there.
    def rule_counts(id, valid)
      counts = COUNTS.to_h do |key|
        [key, valid.sum { |run| run.fetch('score').fetch('by_rule').fetch(id).fetch(key, 0) }]
      end
      counts.merge(rates(counts))
    end

    def rates(counts)
      tp = counts.fetch('true_positives')
      { 'precision' => ratio(tp, tp + counts.fetch('false_positives')),
        'recall' => ratio(tp, tp + counts.fetch('misses')) }
    end

    def case_metrics(id, valid)
      runs = valid.select { |run| run.fetch('case') == id }
      { 'valid_reviews' => runs.size, 'exact_matches' => runs.count { |run| run.fetch('score').fetch('passed') },
        'outcome_vector_repeat_agreement' => pair_agreement(runs.map do |run|
          RULES.map { |rule| run.fetch('score').fetch('actual_outcomes').fetch(rule) }
        end) }
    end

    def pair_agreement(values)
      return nil if values.size < 2

      equal_pairs = values.tally.values.sum { |count| count * (count - 1) }
      equal_pairs.fdiv(values.size * (values.size - 1))
    end

    def probability_variance(valid)
      valid.group_by { |run| run.fetch('case') }.transform_values do |runs|
        signals = Hash.new { |hash, key| hash[key] = [] }
        runs.each do |run|
          run.fetch('report').fetch('rules').each do |id, rule|
            rule.fetch('readings').each_with_index do |values, batch|
              # Reports written since 2026-09-20 always carry fingerprints. The committed docs/verification
              # reports predate them and are still analysed offline, so batch position stands in for those.
              identity = if rule.key?('question_fingerprints')
                           rule.fetch('question_fingerprints').fetch(batch)
                         else
                           "legacy-#{batch}"
                         end
              values.each { |question, value| signals["#{id}/#{identity}/#{question}"] << value }
            end
          end
        end
        signals.transform_values do |values|
          average = mean(values)
          variance = values.size < 2 ? nil : values.sum { |value| (value - average)**2 }.fdiv(values.size - 1)
          { 'samples' => values.size, 'mean' => average, 'sample_variance' => variance }
        end
      end
    end

    def usage
      cost = @runs.sum { |run| run.fetch('estimated_usd') }
      { 'input_tokens' => @runs.sum { |run| run.fetch('input_tokens') }, 'estimated_usd' => cost,
        'reserved_usd' => @runs.sum { |run| run.fetch('reserved_usd') },
        'request_attempts' => @runs.sum { |run| run.fetch('attempts') },
        'mean_estimated_usd_per_observed_review' => ratio(cost, @runs.size) }
    end

    def distribution(values)
      sorted = values.sort
      { 'samples' => values.size, 'mean' => mean(values),
        'p50' => sorted.empty? ? nil : sorted[(sorted.size * 0.50).ceil - 1],
        'p95' => sorted.empty? ? nil : sorted[(sorted.size * 0.95).ceil - 1] }
    end

    def mean(values)
      ratio(values.sum, values.size)
    end

    def ratio(numerator, denominator)
      denominator.zero? ? nil : numerator.fdiv(denominator)
    end

    def percent(value)
      value.nil? ? 'unavailable' : format('%.2f%%', value * 100)
    end

    def number(value)
      value.nil? ? 'unavailable' : format('%.4f', value)
    end

    def validate!
      unless [true, false].include?(@report.fetch('live')) &&
             [true, false].include?(@report.fetch('labels_reviewed')) && @report.fetch('versions').is_a?(Hash) &&
             %w[development holdout].include?(@report.fetch('split'))
        raise InvalidInput, 'Invalid evaluation metadata'
      end

      nonnegative!(@report.fetch('seconds')) if @report.key?('seconds')
      if @report.key?('metrics') && !@report.fetch('metrics').is_a?(Hash)
        raise InvalidInput, 'Invalid finalized metrics'
      end
      if @report.key?('completed') && ![true, false].include?(@report.fetch('completed'))
        raise InvalidInput, 'Invalid completion marker'
      end

      repeats = @report.fetch('repetitions')
      valid_ids = @case_ids.is_a?(Array) && !@case_ids.empty? &&
                  @case_ids.all? { |id| id.is_a?(String) && !id.empty? } && @case_ids.uniq == @case_ids
      unless repeats.is_a?(Integer) && (1..100).cover?(repeats) && valid_ids && @runs.is_a?(Array)
        raise InvalidInput, 'Invalid case inventory or repetitions'
      end

      expected = @case_ids.product((1..repeats).to_a)
      pairs = @runs.map { |run| run.values_at('case', 'repeat') }
      unless pairs.uniq == pairs && (pairs - expected).empty?
        raise InvalidInput, 'Duplicate or unexpected case/repeat pair'
      end

      @runs.each do |run|
        unless run.is_a?(Hash) && run['score'].is_a?(Hash) && run['report'].is_a?(Hash) &&
               run['score']['by_rule'].is_a?(Hash) && run['report']['rules'].is_a?(Hash)
          raise InvalidInput, 'Invalid review record'
        end

        score = run.fetch('score')
        unless [true, false].include?(score.fetch('passed')) &&
               %w[complete incomplete failed].include?(run.fetch('report').fetch('status'))
          raise InvalidInput, 'Invalid review status'
        end

        %w[actual_outcomes expected_outcomes].each do |key|
          outcomes = score.fetch(key)
          unless outcomes.is_a?(Hash) && outcomes.keys.sort == RULES && (outcomes.values - OUTCOMES).empty?
            raise InvalidInput, 'Invalid rule outcome inventory'
          end
        end
        raise InvalidInput, 'Invalid per-rule scores' unless score.fetch('by_rule').keys.sort == RULES

        score.fetch('by_rule').each_value do |counts|
          %w[true_positives false_positives misses].each do |key|
            value = counts.fetch(key)
            raise InvalidInput, 'Invalid finding count' unless value.is_a?(Integer) && value >= 0
          end
        end
        %w[input_tokens estimated_usd reserved_usd attempts].each { |key| nonnegative!(run.fetch(key)) }
        nonnegative!(run['review_seconds']) if run.key?('review_seconds')
        rules = run.fetch('report').fetch('rules')
        raise InvalidInput, 'Invalid rule inventory' unless rules.keys.sort == RULES

        unless rules.transform_values { |rule| rule.fetch('outcome') } == score.fetch('actual_outcomes')
          raise InvalidInput, 'Scored outcomes differ from the review'
        end
        if score.fetch('passed') && score.fetch('actual_outcomes') != score.fetch('expected_outcomes')
          raise InvalidInput, 'Contradictory exact-match score'
        end

        rules.each_value do |rule|
          unless rule.is_a?(Hash) && rule['readings'].is_a?(Array) && rule['readings'].all?(Hash)
            raise InvalidInput, 'Invalid readings'
          end

          if rule.key?('question_fingerprints')
            fingerprints = rule.fetch('question_fingerprints')
            unless fingerprints.is_a?(Array) && fingerprints.size == rule.fetch('readings').size &&
                   fingerprints.all? { |value| value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/) }
              raise InvalidInput, 'Invalid question fingerprints'
            end
          end
          rule.fetch('readings').each do |reading|
            reading.each_value do |value|
              nonnegative!(value)
              raise InvalidInput, 'Invalid probability' if value > 1
            end
          end
        end
      end
      @runs.group_by { |run| run.fetch('case') }.each_value do |runs|
        snapshots = runs.map { |run| run.fetch('report').fetch('snapshot') }.uniq
        labels = runs.map { |run| run.fetch('score').fetch('expected_outcomes') }.uniq
        raise InvalidInput, 'Repeated cases must use fixed inputs and labels' unless snapshots.one? && labels.one?
      end
    end

    def nonnegative!(value)
      return if value.is_a?(Numeric) && value.finite? && value >= 0

      raise InvalidInput, 'Invalid numeric measurement'
    end
  end
end
