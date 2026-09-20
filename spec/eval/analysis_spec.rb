# frozen_string_literal: true

RSpec.describe SlopGuard::EvaluationAnalysis do
  let(:ids) { %w[missing_test corrected] }
  let(:fingerprint) { 'f' * 64 }

  def row(id:, repeat:, actual: 'concern', expected: 'concern', failed: false, reading: 0.8)
    outcomes = %w[G1 G2 G3 G4].to_h { |rule| [rule, rule == 'G1' ? actual : 'not_applicable'] }
    expected_outcomes = outcomes.merge('G1' => expected)
    by_rule = outcomes.to_h do |rule, outcome|
      positive = expected_outcomes[rule] == 'concern'
      found = outcome == 'concern'
      [rule, { 'true_positives' => positive && found ? 1 : 0, 'false_positives' => !positive && found ? 1 : 0,
               'misses' => positive && !found ? 1 : 0 }]
    end
    { 'case' => id, 'repeat' => repeat, 'input_tokens' => 100, 'attempts' => 1,
      'estimated_usd' => 0.0000042, 'reserved_usd' => 0.002688, 'review_seconds' => repeat.to_f,
      'score' => { 'passed' => !failed && actual == expected, 'actual_outcomes' => outcomes,
                   'expected_outcomes' => expected_outcomes, 'by_rule' => by_rule },
      'report' => { 'snapshot' => id, 'status' => failed ? 'failed' : 'complete',
                    'rules' => outcomes.to_h do |rule, outcome|
                      [rule, { 'outcome' => outcome, 'readings' => [{ 'concern' => reading }],
                               'question_fingerprints' => [fingerprint] }]
                    end } }
  end

  let(:report) do
    { 'live' => true, 'labels_reviewed' => false, 'split' => 'development', 'versions' => { 'model' => 'test' },
      'repetitions' => 3, 'seconds' => 6, 'metrics' => {},
      'runs' => ids.flat_map { |id| (1..3).map { |repeat| row(id: id, repeat: repeat) } } }
  end

  def analyze(source = report)
    described_class.new(source, case_ids: ids).to_h
  end

  it 'separates distinct examples from repeated observations and reports known costs and latency' do
    result = analyze
    expect(result.values_at('distinct_cases', 'expected_reviews', 'observed_reviews')).to eq([2, 6, 6])
    expect(result['exact_match_rate_observed']).to eq(1.0)
    expect(result['review_latency_seconds']).to eq('samples' => 6, 'mean' => 2.0, 'p50' => 2.0, 'p95' => 3.0)
    expect(result['usage']['estimated_usd']).to be_within(1e-10).of(0.0000252)
    expect(result['usage']['reserved_usd']).to be_within(1e-10).of(0.016128)
    expect(result['labels_reviewed']).to be(false)
  end

  it 'reports a consistently wrong reviewer as stable but inaccurate' do
    report['runs'] = ids.flat_map do |id|
      (1..3).map { |repeat| row(id: id, repeat: repeat, actual: 'no_concern') }
    end
    result = analyze
    rule = result['by_rule']['G1']
    expect(rule['accuracy']).to eq(0.0)
    expect(rule['mean_case_repeat_agreement']).to eq(1.0)
    expect(rule['confusion_expected_actual']['concern']['no_concern']).to eq(6)
    expect(result['exact_matches']).to eq(0)
  end

  it 'calculates pair agreement within each case and sample variance on observed readings' do
    report['runs'][2] = row(id: ids.first, repeat: 3, actual: 'inconclusive', reading: 0.5)
    result = analyze
    expect(result['by_rule']['G1']['accuracy']).to be_within(1e-10).of(5.0 / 6)
    expect(result['per_case'][ids.first]['outcome_vector_repeat_agreement']).to eq(1.0 / 3)
    expect(result['by_rule']['G1']['mean_case_repeat_agreement']).to eq(2.0 / 3)
    signal = result['probability_variance'][ids.first]["G1/#{fingerprint}/concern"]
    expect(signal['mean']).to be_within(1e-10).of(0.7)
    expect(signal['sample_variance']).to be_within(1e-10).of(0.03)
  end

  it 'does not mistake the right outcome with a wrong finding anchor for correct detection' do
    report['runs'].first['score']['by_rule']['G1'] = { 'true_positives' => 0, 'false_positives' => 1, 'misses' => 1 }
    report['runs'].first['score']['passed'] = false
    rule = analyze['by_rule']['G1']
    expect(rule['accuracy']).to eq(1.0)
    expect(rule['finding_precision']).to eq(5.0 / 6)
    expect(rule['finding_recall']).to eq(5.0 / 6)
    expect(analyze['exact_matches']).to eq(5)
  end

  it 'counts a correct abstention as agreement and an unnecessary abstention as disagreement' do
    report['runs'][0] = row(id: ids.first, repeat: 1, actual: 'inconclusive')
    report['runs'][3..] = (1..3).map do |repeat|
      row(id: ids.last, repeat: repeat, actual: 'inconclusive', expected: 'inconclusive')
    end
    result = analyze
    confusion = result['by_rule']['G1']['confusion_expected_actual']
    expect(confusion['concern']['inconclusive']).to eq(1)
    expect(confusion['inconclusive']['inconclusive']).to eq(3)
  end

  it 'excludes provider failures from semantic agreement while exposing end-to-end failure' do
    report['runs'][0] = row(id: ids.first, repeat: 1, failed: true)
    result = analyze
    expect(result['operational_failures']).to eq(1)
    expect(result['by_rule']['G1'].values_at('observations', 'accuracy')).to eq([5, 1.0])
    expect(result['exact_match_rate_observed']).to eq(5.0 / 6)
    expect(result['usage']['request_attempts']).to eq(6)
  end

  it 'does not invent perfect stability, variance or timing for a partial report' do
    report['runs'] = [report['runs'].first]
    report['runs'].first.delete('review_seconds')
    report.delete('metrics')
    result = analyze
    expect(result['complete']).to be(false)
    expect(result['by_rule']['G1']['mean_case_repeat_agreement']).to be_nil
    expect(result['probability_variance'][ids.first]["G1/#{fingerprint}/concern"]['sample_variance']).to be_nil
    expect(result['review_latency_seconds']).to eq('samples' => 0, 'mean' => nil, 'p50' => nil, 'p95' => nil)
    expect(described_class.new(report, case_ids: ids).markdown).to include('PARTIAL', 'PROVISIONAL', 'unavailable')
  end

  it 'does not combine different questions just because they occupy the same batch position' do
    report['runs'].each do |run|
      fingerprint = run['repeat'] == 1 ? 'a' * 64 : 'b' * 64
      run['report']['rules']['G1']['question_fingerprints'] = [fingerprint]
    end
    signals = analyze['probability_variance'][ids.first]
    expect(signals["G1/#{'a' * 64}/concern"]['samples']).to eq(1)
    expect(signals["G1/#{'b' * 64}/concern"]['samples']).to eq(2)
  end

  it 'rejects duplicate observations and changing inputs or expected labels across repeats' do
    report['runs'][1] = report['runs'][0].dup
    expect { analyze }.to raise_error(SlopGuard::InvalidInput, /Duplicate/)
    report['runs'][1] = row(id: ids.first, repeat: 2)
    report['runs'][1]['report']['snapshot'] = 'changed'
    expect { analyze }.to raise_error(SlopGuard::InvalidInput, /fixed inputs/)
  end

  it 'returns null agreement for all failed observations instead of reporting 100 percent' do
    report['runs'] = [row(id: ids.first, repeat: 1, failed: true)]
    expect(analyze['by_rule']['G1']['accuracy']).to be_nil
    expect(analyze['by_rule']['G1']['mean_case_repeat_agreement']).to be_nil
  end
end
