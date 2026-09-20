# frozen_string_literal: true

RSpec.describe 'design decisions' do
  let(:dataset) { fixture_dataset }

  def review(id, global:, candidate:)
    client = stub_client do |_state, questions|
      if questions.key?('concern')
        global
      elsif questions.key?('abstraction') || questions.key?('counting_presentation')
        questions.to_h { |key, _| [key, candidate.fetch(key, 0.05)] }
      else
        questions.to_h { |key, _| [key, key == 'clear' ? 0.95 : 0.05] }
      end
    end
    SlopGuard::Evaluator.new(client: client).call(demo_snapshot(dataset.input(id)))
  end

  it 'requires the abstraction to lack both consumers and a present constraint' do
    result = review('g4-violation', global: { 'applicable' => 0.95, 'concern' => 0.95 },
                                    candidate: { 'abstraction' => 0.95 })
    expect(result.dig('rules', 'G4', 'outcome')).to eq('concern')
    justified = review('g4-legitimate', global: { 'applicable' => 0.95, 'concern' => 0.05 },
                                        candidate: { 'abstraction' => 0.95, 'constraint' => 0.95 })
    expect(justified.dig('rules', 'G4', 'outcome')).to eq('no_concern')
  end

  it 'requires responsibility mixing and a concrete consequence without justification' do
    result = review('g3-violation', global: { 'applicable' => 0.95, 'concern' => 0.95 },
                                    candidate: { 'counting_presentation' => 0.95, 'consequence' => 0.95 })
    expect(result.dig('rules', 'G3', 'outcome')).to eq('concern')
    justified = review('g3-legitimate', global: { 'applicable' => 0.95, 'concern' => 0.05 },
                                        candidate: { 'counting_presentation' => 0.95, 'consequence' => 0.95,
                                                     'justified' => 0.95 })
    expect(justified.dig('rules', 'G3', 'outcome')).to eq('no_concern')
  end

  it 'reports a coverage gap when global and candidate judgments disagree' do
    result = review('g4-violation', global: { 'applicable' => 0.95, 'concern' => 0.95 },
                                    candidate: { 'abstraction' => 0.95, 'constraint' => 0.95 })
    expect(result.dig('rules', 'G4', 'outcome')).to eq('inconclusive')
  end
end
