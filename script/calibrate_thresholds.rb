# frozen_string_literal: true

require 'bundler/setup'
require_relative '../lib/slop_guard'

module SlopGuard
  # Reuses the production evaluator; only the two numeric rule thresholds vary.
  class ThresholdCalibration
    class MissingReading < StandardError; end

    # Limits the production evaluator to one rule during a sweep.
    class SingleRule < Rules
      def initialize(id, rule)
        super()
        @definitions = { id => rule }
        @revision = SlopGuard.digest(definitions)
      end
    end

    # Recovers request identities while reproducing the original readings.
    class Capture
      attr_reader :transcript

      def initialize(readings)
        @remaining = readings.dup
        @transcript = Hash.new { |hash, key| hash[key] = [] }
      end

      def ask(state, questions)
        values = @remaining.shift
        unless values && values.keys == questions.keys
          raise InvalidInput,
                'Saved question IDs do not match current questions'
        end

        transcript[SlopGuard.digest([state, questions])] << values
        values
      end

      def complete?
        @remaining.empty?
      end
    end

    # Rejects unrecorded questions rather than guessing their readings.
    class Replay
      def initialize(transcript)
        @remaining = transcript.transform_values(&:dup)
      end

      def ask(state, questions)
        values = @remaining[SlopGuard.digest([state, questions])]&.shift
        raise MissingReading, 'Thresholds require an unrecorded question; no answer was inferred' unless values

        values
      end
    end

    def initialize(source:, dataset: Dataset.new(File.join(ROOT, 'eval')))
      @source = source
      @dataset = dataset
      @rules = Rules.new
      @runner = EvalRunner.new(dataset: dataset, rules: @rules)
    end

    def run
      verify_source!
      prepared = @source.fetch('runs').map do |run|
        snapshot = Snapshot.new(@dataset.input(run.fetch('case')))
        unless snapshot.identity == run.fetch('report').fetch('snapshot')
          raise InvalidInput,
                'Snapshot changed since recording'
        end

        transcripts = @rules.definitions.to_h do |id, rule|
          capture = Capture.new(run.fetch('report').fetch('rules').fetch(id).fetch('readings'))
          replayed = Evaluator.new(client: capture, rules: SingleRule.new(id, rule)).call(snapshot)
          unless capture.complete? && replayed.fetch('rules').fetch(id) == run.fetch('report').fetch('rules').fetch(id)
            raise InvalidInput, 'Original thresholds do not reproduce the saved rule result exactly'
          end

          [id, capture.transcript]
        end
        [run, snapshot, @dataset.labels(run.fetch('case')), transcripts]
      end
      results = @rules.definitions.to_h do |id, rule|
        grid = (50..95).step(5).to_a.product((5..45).step(5).to_a).map { |high, low| [high / 100.0, low / 100.0] }
        baseline = measure(id, rule, prepared)
        candidates = grid.map { |high, low| measure(id, rule.merge('high' => high, 'low' => low), prepared) }
        eligible = candidates.select do |point|
          point['unavailable'].zero? && point['false_positives'].zero? &&
            point['correct_abstentions'] == baseline['correct_abstentions']
        end
        best = eligible.max_by do |point|
          [point['true_positives'], point['exact_rule_matches'], -point['unnecessary_abstentions'],
           -(point['high'] - rule['high']).abs - (point['low'] - rule['low']).abs]
        end
        [id, { 'baseline' => baseline, 'best_replay' => best, 'candidates' => candidates }]
      end
      { 'mode' => 'offline_development_replay', 'live_qualified' => false, 'versions' => @source.fetch('versions'),
        'source_report_digest' => SlopGuard.digest(@source),
        'calibrator_sha256' => Digest::SHA256.file(__FILE__).hexdigest,
        'labels_reviewed' => @source['labels_reviewed'], 'repetitions' => @source['repetitions'],
        'runs' => prepared.size, 'grid' => { 'high' => '0.50..0.95 step 0.05', 'low' => '0.05..0.45 step 0.05' },
        'selection' => 'Complete replay, zero false positives, preserve correct abstentions; ' \
                       'maximize true positives then exact rule matches then minimize unnecessary abstentions ' \
                       'then threshold movement.',
        'rules' => results }
    end

    private

    def verify_source!
      unless @source['live'] == true && @source['split'] == 'development'
        raise InvalidInput,
              'Only a live development report can be calibrated'
      end
      unless @source['versions'] == @runner.versions
        raise InvalidInput,
              'Source versions differ from the current evaluator, rules or dataset'
      end

      expected = @dataset.cases('development').map { |entry| entry.fetch('id') }.sort
      runs = @source.fetch('runs')
      repeats = @source.fetch('repetitions')
      valid = repeats.is_a?(Integer) && (1..3).cover?(repeats) && runs.size == expected.size * repeats &&
              (1..repeats).all? do |repeat|
                selected = runs.select { |run| run['repeat'] == repeat }
                selected.map { |run| run['case'] }.sort == expected
              end
      raise InvalidInput, 'Source must contain every development case exactly once per repetition' unless valid
      raise InvalidInput, 'Source contains provider failures' if runs.any? do |run|
        run.fetch('report')['status'] == 'failed'
      end
    end

    def measure(id, rule, prepared)
      result = rule.slice('high', 'low').merge(
        'exact_rule_matches' => 0, 'unavailable' => 0, 'true_positives' => 0, 'false_positives' => 0,
        'misses' => 0, 'correct_abstentions' => 0, 'unnecessary_abstentions' => 0, 'outcomes' => {}
      )
      prepared.each do |run, snapshot, labels, transcripts|
        key = "#{run.fetch('case')}/#{run.fetch('repeat')}"
        begin
          report = Evaluator.new(client: Replay.new(transcripts.fetch(id)),
                                 rules: SingleRule.new(id, rule)).call(snapshot)
          findings = labels.fetch('findings').select { |finding| finding['rule'] == id }
          scoped = { 'outcomes' => labels.fetch('outcomes').slice(id), 'findings' => findings }
          score = @runner.score(report, scoped)
          result['exact_rule_matches'] += 1 if score['passed']
          %w[true_positives false_positives misses correct_abstentions unnecessary_abstentions].each do |metric|
            result[metric] += score.fetch(metric)
          end
          result['outcomes'][key] = report.fetch('rules').fetch(id).fetch('outcome')
        rescue MissingReading
          result['unavailable'] += 1
          result['outcomes'][key] = 'unavailable'
        end
      end
      result
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    unless ARGV.size == 2
      raise SlopGuard::InvalidInput,
            'Usage: ruby script/calibrate_thresholds.rb SOURCE_REPORT OUTPUT_REPORT'
    end

    source = JSON.parse(File.read(ARGV[0]))
    result = SlopGuard::ThresholdCalibration.new(source: source).run
    FileUtils.mkdir_p(File.dirname(ARGV[1]))
    File.write(ARGV[1], "#{JSON.pretty_generate(result)}\n")
    puts JSON.pretty_generate(result.fetch('rules').transform_values { |rule| rule.slice('baseline', 'best_replay') })
  rescue SlopGuard::Error, Errno::ENOENT, JSON::ParserError => e
    warn e.message
    exit 2
  end
end
