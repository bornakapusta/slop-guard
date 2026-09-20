# frozen_string_literal: true

RSpec.describe SlopGuard::Evaluator do
  let(:dataset) { fixture_dataset }
  let(:snapshot) { demo_snapshot(dataset.input('g1-violation')) }

  def answers(questions, missing: 0.95, covered: false)
    questions.to_h do |id, _|
      value = case id
              when 'clear' then 0.95
              when 'applicable' then questions.key?('missing') ? 0.95 : 0.05
              when 'missing' then missing
              else id.start_with?('exercise_', 'assert_') && covered ? 0.95 : 0.05
              end
      [id, value]
    end
  end

  it 'finds a missing test only with consistent complete evidence' do
    client = stub_client { |_state, questions| answers(questions) }
    report = described_class.new(client: client).call(snapshot)
    expect(report.dig('rules', 'G1', 'outcome')).to eq('concern')
    expect(report.dig('rules', 'G1', 'findings').first['topic']).to eq('behavior')
  end

  it 'abstains on conflicting answers instead of ignoring an existing test' do
    client = stub_client { |_state, questions| answers(questions, covered: true) }
    report = described_class.new(client: client).call(snapshot)
    expect(report.dig('rules', 'G1', 'outcome')).to eq('inconclusive')
  end

  it 'accepts a supported existing test and treats the threshold boundary consistently' do
    client = stub_client { |_state, questions| answers(questions, missing: 0.20, covered: true) }
    expect(described_class.new(client: client).call(snapshot).dig('rules', 'G1', 'outcome')).to eq('no_concern')
    client = stub_client { |_state, questions| answers(questions, missing: 0.85) }
    expect(described_class.new(client: client).call(snapshot).dig('rules', 'G1', 'outcome')).to eq('concern')
  end

  it 'does not call Jev when required evidence is missing' do
    client = silent_client
    expect(client).not_to receive(:ask)
    input = demo_snapshot(dataset.input('g1-incomplete'))
    report = described_class.new(client: client).call(input)
    expect(report['rules'].values.map { |rule| rule['outcome'] }.uniq).to eq(['inconclusive'])
  end

  it 'preserves completed findings when a later rule fails' do
    client = stub_client do |_state, questions|
      raise SlopGuard::ProviderError, 'Jev unavailable' unless questions.key?('missing')

      answers(questions)
    end
    report = described_class.new(client: client).call(snapshot)
    expect(report['status']).to eq('failed')
    expect(report.dig('rules', 'G1', 'outcome')).to eq('concern')
    expect(report.dig('rules', 'G3', 'outcome')).to eq('inconclusive')
  end

  it 'skips an empty diff without calling Jev' do
    input = dataset.input('g1-fixed')
    input['before'] = input['files']
    client = silent_client
    expect(client).not_to receive(:ask)
    report = described_class.new(client: client).call(demo_snapshot(input))
    expect(report['rules'].values.map { |rule| rule['outcome'] }.uniq).to eq(['not_applicable'])
  end
end
