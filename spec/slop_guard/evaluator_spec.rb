# frozen_string_literal: true

RSpec.describe SlopGuard::Evaluator do
  let(:dataset) { fixture_dataset }
  let(:snapshot) { demo_snapshot(dataset.input('g1-violation')) }

  # Question IDs are "<scenario>/<question>" within one batched ask; a lone 'applicable' means no scenarios.
  def answers(questions, missing: 0.95, covered: false)
    scenarios = questions.keys.any? { |id| id.end_with?('/missing') }
    questions.to_h do |id, _|
      value = case id.split('/').last
              when 'clear' then 0.95
              when 'applicable' then scenarios ? 0.95 : 0.05
              when 'missing' then missing
              else id.split('/').last.start_with?('exercise_', 'assert_') && covered ? 0.95 : 0.05
              end
      [id, value]
    end
  end

  it 'finds a missing test only with consistent complete evidence, asking once per rule' do
    asks = []
    client = stub_client do |state, questions|
      asks << questions.keys
      expect(questions.values.map { |q| q['instructions'] }.join).not_to include(state['scenarios'].first.last)
      answers(questions)
    end
    report = described_class.new(client: client, rules: demo_rules).call(snapshot)
    expect(report['report_version']).to eq(1)
    expect(report.dig('rules', 'G1', 'outcome')).to eq('concern')
    finding = report.dig('rules', 'G1', 'findings').first
    expect(finding.values_at('topic', 'severity')).to eq(%w[behavior advisory])
    expect(finding['id']).to match(/\A\h{64}\z/)
    expect(finding['anchor']['side']).to eq('head')
    expect(asks.count { |keys| keys.any? { |key| key.end_with?('/missing') } }).to eq(1)
  end

  it 'abstains on conflicting answers instead of ignoring an existing test' do
    client = stub_client { |_state, questions| answers(questions, covered: true) }
    report = described_class.new(client: client, rules: demo_rules).call(snapshot)
    expect(report.dig('rules', 'G1', 'outcome')).to eq('inconclusive')
  end

  it 'accepts a supported existing test and treats the threshold boundary consistently' do
    client = stub_client { |_state, questions| answers(questions, missing: 0.20, covered: true) }
    expect(described_class.new(client: client, rules: demo_rules).call(snapshot).dig('rules', 'G1',
                                                                                     'outcome')).to eq('no_concern')
    client = stub_client { |_state, questions| answers(questions, missing: 0.85) }
    expect(described_class.new(client: client, rules: demo_rules).call(snapshot).dig('rules', 'G1',
                                                                                     'outcome')).to eq('concern')
  end

  it 'does not call Jev when required evidence is missing' do
    client = silent_client
    expect(client).not_to receive(:ask)
    input = demo_snapshot(dataset.input('g1-incomplete'))
    report = described_class.new(client: client, rules: demo_rules).call(input)
    expect(report['rules'].values.map { |rule| rule['outcome'] }.uniq).to eq(['inconclusive'])
  end

  it 'preserves completed findings when a later rule fails' do
    client = stub_client do |_state, questions|
      raise SlopGuard::ProviderError, 'Jev unavailable' unless questions.keys.any? { |key| key.end_with?('/missing') }

      answers(questions)
    end
    report = described_class.new(client: client, rules: demo_rules).call(snapshot)
    expect(report['status']).to eq('failed')
    expect(report.dig('rules', 'G1', 'outcome')).to eq('concern')
    expect(report.dig('rules', 'G3', 'outcome')).to eq('inconclusive')
  end

  it 'does not spend reservations on later rules after a provider failure' do
    asks = 0
    client = stub_client do |_state, _questions|
      asks += 1
      raise SlopGuard::ProviderError, 'Jev returned HTTP 401'
    end
    report = described_class.new(client: client, rules: demo_rules).call(snapshot)
    expect(asks).to eq(1)
    expect(report['status']).to eq('failed')
    expect(report['rules'].values.map { |rule| rule['outcome'] }.uniq).to eq(['inconclusive'])
    expect(report.dig('rules', 'G4', 'gaps').first).to include('Not attempted', 'HTTP 401')
  end

  it 'skips an empty diff without calling Jev' do
    input = dataset.input('g1-fixed')
    input['before'] = input['files']
    client = silent_client
    expect(client).not_to receive(:ask)
    report = described_class.new(client: client, rules: demo_rules).call(demo_snapshot(input))
    expect(report['rules'].values.map { |rule| rule['outcome'] }.uniq).to eq(['not_applicable'])
  end
end
