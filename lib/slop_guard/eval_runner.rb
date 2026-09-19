# frozen_string_literal: true

module SlopGuard
  class EvalRunner
    attr_reader :dataset, :rules

    def initialize(dataset:, rules: Rules.new)
      @dataset = dataset
      @rules = rules
    end

    def versions
      sources = Dir[File.join(ROOT, 'lib/**/*.rb')].to_h { |file| [file.delete_prefix("#{ROOT}/"), File.read(file)] }
      artifacts = Dir[dataset.root.join('**/*.json')].to_h { |file| [file.delete_prefix("#{dataset.root}/"), File.read(file)] }
      { 'model' => JevClient::MODEL, 'rules' => rules.revision, 'engine' => SlopGuard.digest(sources),
        'dataset' => SlopGuard.digest(artifacts), 'lockfile' => Digest::SHA256.file(File.join(ROOT, 'Gemfile.lock')).hexdigest,
        'ruby' => RUBY_VERSION, 'profile' => Digest::SHA256.file(File.join(ROOT, 'config/demo.yml')).hexdigest }
    end

    def score(report, labels)
      actual = report.fetch('rules').values.flat_map { |rule| rule.fetch('findings') }
      expected = labels.fetch('findings')
      matched = []
      false_positives = 0
      actual.each do |finding|
        index = expected.each_index.find do |i|
          !matched.include?(i) && expected[i]['rule'] == finding['rule'] && expected[i]['topic'] == finding['topic'] &&
            expected[i]['anchors'].include?(finding['anchor'])
        end
        index ? matched << index : false_positives += 1
      end
      outcomes = report.fetch('rules').transform_values { |rule| rule.fetch('outcome') }
      correct_abstentions = labels.fetch('outcomes').count { |id, outcome| outcome == 'inconclusive' && outcomes[id] == outcome }
      unnecessary = outcomes.count { |id, outcome| outcome == 'inconclusive' && labels['outcomes'][id] != outcome }
      { 'passed' => report['status'] != 'failed' && outcomes == labels['outcomes'] && matched.size == expected.size && false_positives.zero?,
        'true_positives' => matched.size, 'false_positives' => false_positives, 'misses' => expected.size - matched.size,
        'correct_abstentions' => correct_abstentions, 'unnecessary_abstentions' => unnecessary,
        'actual_outcomes' => outcomes, 'expected_outcomes' => labels['outcomes'],
        'by_rule' => labels['outcomes'].keys.to_h do |id|
          count = matched.count { |i| expected[i]['rule'] == id }
          expected_count = expected.count { |item| item['rule'] == id }
          actual_count = actual.count { |item| item['rule'] == id }
          [id, { 'true_positives' => count, 'false_positives' => actual_count - count, 'misses' => expected_count - count,
                 'correct_abstentions' => (outcomes[id] == 'inconclusive' && labels['outcomes'][id] == 'inconclusive' ? 1 : 0),
                 'unnecessary_abstentions' => (outcomes[id] == 'inconclusive' && labels['outcomes'][id] != 'inconclusive' ? 1 : 0) }]
        end }
    end

    def run(split:, repetitions:, directory:, client_factory:, live: false)
      dataset.validate!
      raise InvalidInput, 'Split must be development or holdout' unless %w[development holdout].include?(split)
      raise InvalidInput, 'Repetitions must be between 1 and 3' unless (1..3).cover?(repetitions)
      FileUtils.mkdir_p(directory)
      result = { 'live' => live, 'split' => split, 'versions' => versions, 'repetitions' => repetitions, 'labels_reviewed' => dataset.manifest['labels_reviewed'] == true, 'runs' => [], 'passed' => false }
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      repetitions.times do |repeat|
        dataset.cases(split).each do |entry|
          budget = Budget.new(ledger: File.join(directory, 'requests.jsonl'))
          client = client_factory.call(budget)
          report = Evaluator.new(client: client, rules: rules).call(Snapshot.new(dataset.input(entry['id'])))
          run = { 'case' => entry['id'], 'repeat' => repeat + 1, 'report' => report,
                  'score' => score(report, dataset.labels(entry['id'])), 'attempts' => budget.attempts,
                  'input_tokens' => budget.usage, 'reserved_usd' => budget.reserved,
                  'estimated_usd' => budget.usage * 0.042 / 1_000_000 }
          result['runs'] << run
          save(directory, result)
        end
      end
      result['passed'] = result['runs'].all? { |run| run['score']['passed'] }
      result['seconds'] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
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
      unless report['live'] && report['passed'] && report['split'] == 'development' && report['versions'] == versions &&
             report.fetch('runs').map { |run| run['case'] }.uniq.sort == expected
        raise InvalidInput, 'A complete passing live development report for these exact versions is required'
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
