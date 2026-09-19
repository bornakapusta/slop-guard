# frozen_string_literal: true

RSpec.describe 'the evaluation pipeline' do
  it 'executes the real engine repeatedly, records operational failures and never claims replay is live' do
    dataset = SlopGuard::Dataset.new(File.join(SlopGuard::ROOT, 'eval'))
    runner = SlopGuard::EvalRunner.new(dataset: dataset)
    requests = 0
    client = Object.new
    client.define_singleton_method(:ask) do |_state, _questions|
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
