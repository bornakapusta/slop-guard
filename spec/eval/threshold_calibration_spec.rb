# frozen_string_literal: true

require_relative '../../script/calibrate_thresholds'

RSpec.describe SlopGuard::ThresholdCalibration do
  let(:dataset) { fixture_dataset }
  let(:versions) { SlopGuard::EvalRunner.new(dataset: dataset).versions }

  it 'rejects holdout reports before reading cases or labels' do
    expect(dataset).not_to receive(:input)
    expect(dataset).not_to receive(:labels)
    expect { described_class.new(source: { 'live' => true, 'split' => 'holdout' }, dataset: dataset).run }
      .to raise_error(SlopGuard::InvalidInput, /development/)
  end

  it 'rejects stale engine or question versions before replay' do
    source = { 'live' => true, 'split' => 'development', 'versions' => versions.merge('rules' => 'stale') }
    expect { described_class.new(source: source, dataset: dataset).run }
      .to raise_error(SlopGuard::InvalidInput, /versions/)
  end

  it 'rejects a partial development report instead of optimizing its easier subset' do
    source = { 'live' => true, 'split' => 'development', 'versions' => versions, 'runs' => [], 'repetitions' => 1 }
    expect { described_class.new(source: source, dataset: dataset).run }
      .to raise_error(SlopGuard::InvalidInput, /every development case/)
  end

  it 'requires original question IDs and order when recovering the request transcript' do
    capture = described_class::Capture.new([{ 'applicable' => 0.9 }])
    expect { capture.ask({}, { 'concern' => { 'instructions' => 'A different question' } }) }
      .to raise_error(SlopGuard::InvalidInput, /question IDs/)
  end

  it 'never supplies a cached answer to changed evidence or a different question with the same ID' do
    state = { 'source' => 'original' }
    questions = { 'applicable' => { 'instructions' => 'Original question' } }
    capture = described_class::Capture.new([{ 'applicable' => 0.9 }])
    capture.ask(state, questions)
    replay = described_class::Replay.new(capture.transcript)
    expect { replay.ask({ 'source' => 'changed' }, questions) }.to raise_error(described_class::MissingReading)
    expect { replay.ask(state, { 'applicable' => { 'instructions' => 'Changed question' } }) }
      .to raise_error(described_class::MissingReading)
    expect(replay.ask(state, questions)).to eq('applicable' => 0.9)
    expect { replay.ask(state, questions) }.to raise_error(described_class::MissingReading)
  end

  it 'marks a newly entered decision branch unavailable rather than inventing candidate readings' do
    snapshot = SlopGuard::Snapshot.new(dataset.input('g4-violation'))
    original = SlopGuard::Rules.new.definitions.fetch('G4')
    capture = described_class::Capture.new([{ 'applicable' => 0.8, 'concern' => 0.9 }])
    baseline = SlopGuard::Evaluator.new(client: capture,
                                        rules: described_class::SingleRule.new(
                                          'G4', original
                                        )).call(snapshot)
    expect(baseline['rules']['G4']['outcome']).to eq('inconclusive')
    expect(capture.complete?).to be(true)
    lowered = described_class::SingleRule.new('G4', original.merge('high' => 0.75))
    expect { SlopGuard::Evaluator.new(client: described_class::Replay.new(capture.transcript), rules: lowered).call(snapshot) }
      .to raise_error(described_class::MissingReading)
  end
end
