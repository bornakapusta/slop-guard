# frozen_string_literal: true

module SlopGuard
  # Scores saved cases and records fresh evaluation evidence incrementally.
  class EvalRunner
    attr_reader :dataset, :rules

    # Reads a saved evaluation directory. Runs appended to runs.jsonl after the last report.json checkpoint are
    # merged in, so an interrupted session loses nothing that finished.
    def self.load(directory)
      report = JSON.parse(File.read(File.join(directory, 'report.json')))
      raise InvalidInput, 'Malformed evaluation report' unless report.is_a?(Hash) && report['runs'].is_a?(Array)

      log = File.join(directory, 'runs.jsonl')
      if File.file?(log)
        seen = report['runs'].map { |run| run.values_at('case', 'repeat') }
        File.foreach(log) do |line|
          run = JSON.parse(line)
          report['runs'] << run unless seen.include?(run.values_at('case', 'repeat'))
        end
      end
      report
    rescue JSON::ParserError
      raise InvalidInput, 'Malformed evaluation report'
    end

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

    def run(split:, repetitions:, directory:, client_factory:, live: false)
      prepared = prepare(split, repetitions)
      FileUtils.mkdir_p(directory)
      result = { 'live' => live, 'split' => split, 'versions' => versions, 'repetitions' => repetitions,
                 'case_ids' => prepared.map(&:first),
                 'labels_reviewed' => dataset.manifest['labels_reviewed'] == true, 'runs' => [], 'passed' => false }
      start = @clock.call
      repetitions.times do |repeat|
        prepared.each do |id, snapshot, labels|
          run = review_case(id, snapshot, labels, repeat + 1, directory, client_factory)
          result['runs'] << run
          append(directory, run)
        end
        # One checkpoint per repetition; runs.jsonl carries anything finished since.
        save(directory, result)
      end
      finalize(result, prepared.size * repetitions, start)
      save(directory, result)
      result
    end

    def freeze!(development_report, output)
      report = JSON.parse(File.read(development_report))
      expected = dataset.cases('development').map { |entry| entry['id'] }.sort
      unless report['live'] && report['passed'] && report['labels_reviewed'] == true &&
             report['split'] == 'development' && report['versions'] == versions &&
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

    # Prepare once so only model judgments vary between repetitions.
    def prepare(split, repetitions)
      dataset.validate!
      raise InvalidInput, 'Split must be development or holdout' unless %w[development holdout].include?(split)
      unless repetitions.is_a?(Integer) && (1..3).cover?(repetitions)
        raise InvalidInput, 'Repetitions must be between 1 and 3'
      end

      dataset.cases(split).map do |entry|
        id = entry.fetch('id')
        [id, Snapshot.new(dataset.input(id), profile: @profile), dataset.labels(id)]
      end
    end

    def review_case(id, snapshot, labels, repeat, directory, client_factory)
      budget = Budget.new(ledger: File.join(directory, 'requests.jsonl'))
      client = client_factory.call(budget)
      review_start = @clock.call
      report = Evaluator.new(client: client, rules: rules).call(snapshot)
      { 'case' => id, 'repeat' => repeat, 'report' => report,
        'review_seconds' => @clock.call - review_start,
        'score' => score(report, labels), 'attempts' => budget.attempts,
        'input_tokens' => budget.usage, 'reserved_usd' => budget.reserved,
        'estimated_usd' => budget.usage * JevClient::USD_PER_INPUT_TOKEN }
    end

    def finalize(result, expected_runs, start)
      result['completed'] = result['runs'].size == expected_runs
      result['passed'] = result['completed'] && result['runs'].all? { |run| run['score']['passed'] }
      result['seconds'] = @clock.call - start
      result['metrics'] = EvaluationAnalysis.new(result, case_ids: result['case_ids']).metrics
    end

    def append(directory, run)
      File.open(File.join(directory, 'runs.jsonl'), 'a') { |file| file.puts(JSON.generate(run)) }
    end

    def save(directory, result)
      path = File.join(directory, 'report.json')
      File.write("#{path}.tmp", JSON.pretty_generate(result))
      File.rename("#{path}.tmp", path)
    end
  end
end
