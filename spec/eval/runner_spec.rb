# frozen_string_literal: true

RSpec.describe 'the evaluation pipeline' do
  it 'executes the real engine repeatedly, records operational failures and never claims replay is live' do
    dataset = fixture_dataset
    runner = SlopGuard::Eval::Runner.new(dataset: dataset, profile: demo_profile, rules: demo_rules)
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
      expect(result['metrics']['by_rule']['G1'].keys).to include('unnecessary_abstentions', 'precision', 'recall')
      saved = JSON.parse(File.read(File.join(directory, 'report.json')))
      expect(saved).to eq(result)
      expect(File.foreach(File.join(directory, 'runs.jsonl')).count).to eq(24)
    end
  end

  it 'recovers runs finished after the last checkpoint when loading an interrupted directory' do
    Dir.mktmpdir do |directory|
      runs = [{ 'case' => 'a', 'repeat' => 1 }, { 'case' => 'b', 'repeat' => 1 }]
      File.write(File.join(directory, 'report.json'), JSON.generate('runs' => runs.first(1)))
      File.write(File.join(directory, 'runs.jsonl'), runs.map { |run| JSON.generate(run) }.join("\n"))
      expect(SlopGuard::Eval::Runner.load(directory)['runs']).to eq(runs)
      File.write(File.join(directory, 'report.json'), '[]')
      expect { SlopGuard::Eval::Runner.load(directory) }.to raise_error(SlopGuard::InvalidInput, /Malformed/)
    end
  end
end

RSpec.describe 'repeated evaluation runs' do
  let(:dataset) { fixture_dataset }
  let(:runner) { SlopGuard::Eval::Runner.new(dataset: dataset, profile: demo_profile, rules: demo_rules) }

  it 'freezes inputs once, records review latency and fingerprints the exact questions' do
    allow(dataset).to receive(:input).and_call_original
    # Dataset validation loads each input once; preparation loads it once more, never once per repeat.
    expect(dataset).to receive(:input).with('g1-violation').twice.and_call_original
    tick = 0.0
    timed = SlopGuard::Eval::Runner.new(dataset: dataset, profile: demo_profile, rules: demo_rules, clock: lambda {
      tick += 0.125
    })
    client = stub_client { |_state, questions| questions.transform_values { 0.5 } }
    Dir.mktmpdir do |directory|
      result = timed.run(split: 'development', repetitions: 3, directory: directory,
                         client_factory: ->(_) { client })
      expect(result['case_ids'].size).to eq(16)
      expect(result['runs'].size).to eq(48)
      expect(result['runs'].map { |run| run['review_seconds'] }.uniq).to eq([0.125])
      expect(result['runs'].first['report']['rules']['G1']['question_fingerprints'].first).to match(/\A[0-9a-f]{64}\z/)
      expect(result['completed']).to be(true)
      analysis = SlopGuard::Eval::Analysis.new(result, case_ids: result['case_ids']).to_h
      expect(analysis['complete']).to be(true)
      expect(analysis['live']).to be(false)
      expect(analysis['review_latency_seconds']['samples']).to eq(48)
      summary = SlopGuard::Eval::Summary.new(report: result.merge('live' => true),
                                             case_ids: result['case_ids'], reserved: 0, exit_status: 1)
      expect(summary.markdown).to include('Outcome agreement', 'PROVISIONAL', '48/48 reviews')
    end
  end

  it 'limits runs to three repetitions' do
    factory = ->(_) { raise 'must not create a client' }
    Dir.mktmpdir do |directory|
      options = { directory: directory, client_factory: factory, split: 'development', repetitions: 4 }
      expect { runner.run(**options) }.to raise_error(SlopGuard::InvalidInput, /1 and 3/)
    end
  end
end
