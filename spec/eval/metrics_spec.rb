# frozen_string_literal: true

RSpec.describe SlopGuard::EvalRunner do
  let(:dataset) { fixture_dataset }
  let(:runner) { described_class.new(dataset: dataset) }
  let(:labels) { dataset.labels('g1-violation') }

  def report_with(findings, outcome = 'concern')
    rules = labels['outcomes'].to_h { |id, value| [id, { 'outcome' => value, 'findings' => [] }] }
    rules['G1'] = { 'outcome' => outcome, 'findings' => findings }
    { 'status' => 'complete', 'rules' => rules }
  end

  def matching
    expected = labels['findings'].first
    expected.slice('rule', 'topic').merge('anchor' => expected['anchors'].first)
  end

  it 'matches rule, scenario and location, penalizing extra and duplicate accusations' do
    expect(runner.score(report_with([matching]), labels)['passed']).to be(true)
    wrong = matching.merge('anchor' => { 'path' => 'wrong.rb', 'line' => 1 })
    score = runner.score(report_with([wrong]), labels)
    expect(score.values_at('true_positives', 'false_positives', 'misses')).to eq([0, 1, 1])
    duplicate = runner.score(report_with([matching, matching]), labels)
    expect(duplicate['false_positives']).to eq(1)
    expect(duplicate['passed']).to be(false)
  end

  it 'counts an answerable positive abstention as a miss' do
    score = runner.score(report_with([], 'inconclusive'), labels)
    expect(score['misses']).to eq(1)
    expect(score['unnecessary_abstentions']).to eq(1)
  end

  it 'does not freeze provisional labels as qualification' do
    source = { 'live' => true, 'passed' => true, 'split' => 'development', 'versions' => runner.versions,
               'runs' => dataset.cases('development').map { |entry| { 'case' => entry['id'] } },
               'labels_reviewed' => false }
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'report.json')
      File.write(path, JSON.generate(source))
      expect { runner.freeze!(path, File.join(directory, 'frozen.json')) }.to raise_error(SlopGuard::InvalidInput)
    end
  end

  it 'rejects freezing fabricated replay results' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'report.json')
      File.write(path, JSON.generate('live' => false, 'passed' => true))
      expect { runner.freeze!(path, File.join(directory, 'frozen.json')) }.to raise_error(SlopGuard::InvalidInput)
    end
  end
end

RSpec.describe 'evaluation prerequisites' do
  it 'rejects empty datasets rather than treating zero cases as a pass' do
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, 'manifest.json'), JSON.generate('cases' => []))
      dataset = SlopGuard::Dataset.new(directory)
      expect { dataset.validate! }.to raise_error(SlopGuard::InvalidInput, /16 development/)
    end
  end
end
