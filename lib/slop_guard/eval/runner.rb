# frozen_string_literal: true

module SlopGuard
  # Scores saved cases and records fresh evaluation evidence incrementally.
  class EvalRunner
    attr_reader :dataset, :rules

    def initialize(dataset:, profile: Profile.load('demo'), rules: Rules.new(profile.rules_dir),
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @dataset = dataset
      @profile = profile
      @rules = rules
      @clock = clock
    end

    def versions
      sources = Dir[File.join(ROOT, 'lib/**/*.rb')].to_h { |file| [file.delete_prefix("#{ROOT}/"), File.read(file)] }
      artifacts = Dir[dataset.root.join('**/*.json')].to_h do |file|
        [file.delete_prefix("#{dataset.root}/"), File.read(file)]
      end
      { 'model' => JevClient::MODEL, 'rules' => rules.revision, 'engine' => SlopGuard.digest(sources),
        'dataset' => SlopGuard.digest(artifacts),
        'lockfile' => Digest::SHA256.file(File.join(ROOT, 'Gemfile.lock')).hexdigest,
        'ruby' => RUBY_VERSION, 'profile' => SlopGuard.digest(@profile.to_h) }
    end

    def score(report, labels)
      actual = report.fetch('rules').values.flat_map { |rule| rule.fetch('findings') }
      expected = labels.fetch('findings')
      matched = []
      false_positives = 0
      actual.each do |finding|
        anchor = finding.fetch('anchor').slice('path', 'line')
        index = expected.each_index.find do |i|
          !matched.include?(i) && expected[i]['rule'] == finding['rule'] && expected[i]['topic'] == finding['topic'] &&
            expected[i]['anchors'].any? { |candidate| candidate.slice('path', 'line') == anchor }
        end
        index ? matched << index : false_positives += 1
      end
      outcomes = report.fetch('rules').transform_values { |rule| rule.fetch('outcome') }
      correct_abstentions = labels.fetch('outcomes').count do |id, outcome|
        outcome == 'inconclusive' && outcomes[id] == outcome
      end
      unnecessary = outcomes.count { |id, outcome| outcome == 'inconclusive' && labels['outcomes'][id] != outcome }
      passed = report['status'] != 'failed' && outcomes == labels['outcomes'] &&
               matched.size == expected.size && false_positives.zero?
      { 'passed' => passed,
        'true_positives' => matched.size, 'false_positives' => false_positives,
        'misses' => expected.size - matched.size,
        'correct_abstentions' => correct_abstentions, 'unnecessary_abstentions' => unnecessary,
        'actual_outcomes' => outcomes, 'expected_outcomes' => labels['outcomes'],
        'by_rule' => labels['outcomes'].keys.to_h do |id|
          count = matched.count { |i| expected[i]['rule'] == id }
          expected_count = expected.count { |item| item['rule'] == id }
          actual_count = actual.count { |item| item['rule'] == id }
          expected_abstention = labels['outcomes'][id] == 'inconclusive'
          abstained = outcomes[id] == 'inconclusive'
          [id, { 'true_positives' => count, 'false_positives' => actual_count - count,
                 'misses' => expected_count - count,
                 'correct_abstentions' => (abstained && expected_abstention ? 1 : 0),
                 'unnecessary_abstentions' => (abstained && !expected_abstention ? 1 : 0) }]
        end }
    end

    def run(split:, repetitions:, directory:, client_factory:, live: false, benchmark: false)
      dataset.validate!
      raise InvalidInput, 'Split must be development or holdout' unless %w[development holdout].include?(split)
      raise InvalidInput, 'Benchmarks use development cases only' if benchmark && split != 'development'

      maximum = benchmark ? 100 : 3
      unless repetitions.is_a?(Integer) && (1..maximum).cover?(repetitions)
        raise InvalidInput, "Repetitions must be between 1 and #{maximum}"
      end

      # Prepare once so only model judgments vary between repetitions.
      prepared = dataset.cases(split).map do |entry|
        id = entry.fetch('id')
        [id, Snapshot.new(dataset.input(id), profile: @profile), dataset.labels(id)]
      end
      FileUtils.mkdir_p(directory)
      result = { 'live' => live, 'split' => split, 'versions' => versions, 'repetitions' => repetitions,
                 'mode' => benchmark ? 'benchmark' : 'evaluation', 'case_ids' => prepared.map(&:first),
                 'labels_reviewed' => dataset.manifest['labels_reviewed'] == true, 'runs' => [], 'passed' => false }
      start = @clock.call
      catch(:benchmark_failed) do
        repetitions.times do |repeat|
          prepared.each do |id, snapshot, labels|
            budget = Budget.new(ledger: File.join(directory, 'requests.jsonl'))
            client = client_factory.call(budget)
            review_start = @clock.call
            report = Evaluator.new(client: client, rules: rules).call(snapshot)
            run = { 'case' => id, 'repeat' => repeat + 1, 'report' => report,
                    'review_seconds' => @clock.call - review_start,
                    'score' => score(report, labels), 'attempts' => budget.attempts,
                    'input_tokens' => budget.usage, 'reserved_usd' => budget.reserved,
                    'estimated_usd' => budget.usage * 0.042 / 1_000_000 }
            result['runs'] << run
            if benchmark && report.fetch('status') == 'failed'
              result['stopped_reason'] = 'Operational failure; inspect the failed review and request ledger'
              save(directory, result)
              throw :benchmark_failed
            end
            save(directory, result)
          end
        end
      end
      result['completed'] = result['runs'].size == prepared.size * repetitions
      result['passed'] = result['completed'] && result['runs'].all? { |run| run['score']['passed'] }
      result['seconds'] = @clock.call - start
      valid = result['runs'].reject { |run| run['report']['status'] == 'failed' }
      totals = %w[true_positives false_positives misses correct_abstentions unnecessary_abstentions].to_h do |key|
        [key, valid.sum { |run| run['score'][key] }]
      end
      tp = totals['true_positives']
      totals['precision'] = ratio(tp, tp + totals['false_positives'])
      totals['recall'] = ratio(tp, tp + totals['misses'])
      totals['operational_failures'] = result['runs'].size - valid.size
      totals['outcome_flips'] = result['runs'].group_by { |run| run['case'] }.count do |_, runs|
        runs.map { |run| run['score']['actual_outcomes'] }.uniq.size > 1
      end
      totals['by_rule'] = %w[G1 G2 G3 G4].to_h do |id|
        counts = %w[true_positives false_positives misses correct_abstentions unnecessary_abstentions].to_h do |key|
          [key, valid.sum { |run| run['score']['by_rule'][id][key] }]
        end
        counts['precision'] = ratio(counts['true_positives'], counts['true_positives'] + counts['false_positives'])
        counts['recall'] = ratio(counts['true_positives'], counts['true_positives'] + counts['misses'])
        [id, counts]
      end
      result['metrics'] = totals
      result['probability_ranges'] = probability_ranges(result['runs'])
      save(directory, result)
      result
    end

    def freeze!(development_report, output)
      report = JSON.parse(File.read(development_report))
      expected = dataset.cases('development').map { |entry| entry['id'] }.sort
      unless report['live'] && report['passed'] && report['labels_reviewed'] == true &&
             report['mode'] != 'benchmark' && report['split'] == 'development' && report['versions'] == versions &&
             report.fetch('runs').map { |run| run['case'] }.uniq.sort == expected
        raise InvalidInput,
              'A complete passing live development report with reviewed labels for these exact versions is required'
      end

      File.write(output, JSON.pretty_generate(versions))
    end

    def verify_frozen!(path)
      raise InvalidInput, 'Frozen versions do not match current inputs' unless JSON.parse(File.read(path)) == versions
    end

    private

    def probability_ranges(runs)
      runs.group_by { |run| run['case'] }.transform_values do |repeats|
        signals = Hash.new { |hash, key| hash[key] = [] }
        repeats.each do |run|
          run['report']['rules'].each do |id, rule|
            rule['readings'].each_with_index do |values, batch|
              values.each { |question, probability| signals["#{id}/#{batch}/#{question}"] << probability }
            end
          end
        end
        signals.transform_values { |values| { 'min' => values.min, 'max' => values.max, 'samples' => values.size } }
      end
    end

    def ratio(numerator, denominator)
      denominator.zero? ? nil : numerator.fdiv(denominator)
    end

    def save(directory, result)
      path = File.join(directory, 'report.json')
      File.write("#{path}.tmp", JSON.pretty_generate(result))
      File.rename("#{path}.tmp", path)
    end
  end
end
