# frozen_string_literal: true

require_relative '../../script/evaluation_summary'

RSpec.describe 'the evaluation pipeline' do
  it 'executes the real engine repeatedly, records operational failures and never claims replay is live' do
    dataset = fixture_dataset
    runner = SlopGuard::EvalRunner.new(dataset: dataset)
    requests = 0
    client = stub_client do |_state, _questions|
      requests += 1
      raise SlopGuard::ProviderError, 'Controlled offline provider failure'
    end
    Dir.mktmpdir do |directory|
      result = runner.run(split: 'holdout', repetitions: 3, directory: directory, client_factory: ->(_) { client })
      expect(result['runs'].size).to eq(24)
      expect(requests).to be >= 24
      expect(result['live']).to be(false)
      expect(result['passed']).to be(false)
      expect(result['metrics']['operational_failures']).to eq(24)
      expect(result['metrics']['precision']).to be_nil
      saved = JSON.parse(File.read(File.join(directory, 'report.json')))
      expect(saved).to eq(result)
    end
  end
end

RSpec.describe 'benchmark execution' do
  let(:dataset) { fixture_dataset }
  let(:runner) { SlopGuard::EvalRunner.new(dataset: dataset) }

  it 'freezes inputs once, records review latency and fingerprints the exact questions' do
    allow(dataset).to receive(:input).and_call_original
    # Dataset validation loads each input once; preparation loads it once more, never once per repeat.
    expect(dataset).to receive(:input).with('g1-violation').twice.and_call_original
    tick = 0.0
    timed = SlopGuard::EvalRunner.new(dataset: dataset, clock: -> { tick += 0.125 })
    client = stub_client { |_state, questions| questions.transform_values { 0.5 } }
    Dir.mktmpdir do |directory|
      result = timed.run(split: 'development', repetitions: 3, directory: directory,
                         client_factory: ->(_) { client })
      expect(result['case_ids'].size).to eq(16)
      expect(result['runs'].size).to eq(48)
      expect(result['runs'].map { |run| run['review_seconds'] }.uniq).to eq([0.125])
      expect(result['runs'].first['report']['rules']['G1']['question_fingerprints'].first).to match(/\A[0-9a-f]{64}\z/)
      expect(result['mode']).to eq('evaluation')
      expect(result['completed']).to be(true)
      analysis = SlopGuard::EvaluationAnalysis.new(result, case_ids: result['case_ids']).to_h
      expect(analysis['complete']).to be(true)
      expect(analysis['live']).to be(false)
      expect(analysis['review_latency_seconds']['samples']).to eq(48)
      summary = SlopGuard::EvaluationSummary.new(report: result.merge('live' => true),
                                                 case_ids: result['case_ids'], reserved: 0, exit_status: 1)
      expect(summary.markdown).to include('Outcome agreement', 'PROVISIONAL', '48/48 reviews')
    end
  end

  it 'stops a 100-repeat development benchmark on an operational failure and retains partial evidence' do
    client = stub_client { |*| raise SlopGuard::LimitExceeded, 'Evaluation session budget exhausted' }
    Dir.mktmpdir do |directory|
      result = runner.run(split: 'development', repetitions: 100, benchmark: true, directory: directory,
                          client_factory: ->(_) { client })
      expect(result['runs'].size).to eq(1)
      expect(result['completed']).to be(false)
      expect(result['passed']).to be(false)
      expect(result['stopped_reason']).to include('Operational failure')
      saved = JSON.parse(File.read(File.join(directory, 'report.json')))
      expect(saved).to eq(result)
      analysis = SlopGuard::EvaluationAnalysis.new(saved, case_ids: saved['case_ids']).to_h
      expect(analysis.values_at('complete', 'expected_reviews', 'operational_failures')).to eq([false, 1600, 1])
    end
  end

  it 'requires explicit benchmark mode for longer runs and never benchmarks the holdout split' do
    factory = ->(_) { raise 'must not create a client' }
    Dir.mktmpdir do |directory|
      options = { directory: directory, client_factory: factory, split: 'development', repetitions: 4 }
      expect { runner.run(**options) }.to raise_error(SlopGuard::InvalidInput, /1 and 3/)
      expect { runner.run(**options, benchmark: true, repetitions: 101) }
        .to raise_error(SlopGuard::InvalidInput, /1 and 100/)
      expect { runner.run(**options, benchmark: true, split: 'holdout') }
        .to raise_error(SlopGuard::InvalidInput, /development cases only/)
    end
  end
end
