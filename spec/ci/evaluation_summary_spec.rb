# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require_relative '../../script/evaluation_summary'

RSpec.describe SlopGuard::EvaluationSummary do
  let(:cases) { %w[violation fixed] }
  let(:counts) { { 'true_positives' => 1, 'false_positives' => 0, 'misses' => 0, 'unnecessary_abstentions' => 0 } }
  let(:report) do
    { 'live' => true, 'split' => 'development', 'repetitions' => 3, 'passed' => true, 'labels_reviewed' => false,
      'versions' => { 'model' => 'jev-test', 'engine' => 'example' }, 'seconds' => 1.0,
      'metrics' => { 'outcome_flips' => 0, 'by_rule' => %w[G1 G2 G3 G4].to_h { |id| [id, counts.dup] } },
      'runs' => cases.product([1, 2, 3]).map do |id, repeat|
        { 'case' => id, 'repeat' => repeat, 'score' => { 'passed' => true }, 'report' => { 'status' => 'complete' },
          'input_tokens' => 100, 'estimated_usd' => 0.001 }
      end }
  end

  def summarize(data = report, status: 0)
    described_class.new(report: data, case_ids: cases, reserved: 0.02, exit_status: status)
  end

  it 'reports a complete development pass without claiming held-out or provisional-label qualification' do
    summary = summarize
    expect(summary.status).to eq('PASSED DEVELOPMENT LABELS')
    expect(summary.markdown).to include('6/6', 'Provisional labels', '$0.006000', '$0.020000')
    expect(summary.markdown).to include('not actual charges')
  end

  it 'preserves mismatches and operational errors even if the top-level pass flag is inconsistent' do
    report['runs'].first['score']['passed'] = false
    expect(summarize.status).to eq('FAILED')
    report['runs'].first['score']['passed'] = true
    report['runs'].first['report']['status'] = 'failed'
    expect(summarize.status).to eq('FAILED')
  end

  it 'does not present contradictory final metrics as a pass' do
    report['metrics']['by_rule']['G1']['misses'] = 1
    expect(summarize.status).to eq('FAILED')
  end

  it 'rejects invalid finalized duration' do
    report['seconds'] = -1
    expect { summarize }.to raise_error(SlopGuard::InvalidInput, /duration/)
  end

  it 'preserves a nonzero evaluator exit even if every recorded case passed' do
    expect(summarize(status: 2).status).to eq('FAILED')
  end

  it 'labels interrupted data partial and retains reservations beyond completed case usage' do
    report['runs'] = report['runs'].take(2)
    report.delete('metrics')
    report.delete('seconds')
    summary = summarize(status: 124)
    expect(summary.status).to eq('INCOMPLETE')
    expect(summary.markdown).to include('2/6', 'Final metrics and repeat stability are unavailable', '$0.020000')
    expect(summary.markdown).not_to include('| Rule |')
  end

  it 'does not count a full inventory saved before finalization as complete' do
    report.delete('metrics')
    expect(summarize.status).to eq('INCOMPLETE')
  end

  it 'does not let duplicate or unexpected cases stand in for missing repeats' do
    report['runs'][-1] = report['runs'].first.dup
    expect { summarize }.to raise_error(SlopGuard::InvalidInput, /Duplicate/)
  end

  it 'rejects malformed usage and finalized metrics' do
    report['runs'].first['input_tokens'] = 'unknown'
    expect { summarize }.to raise_error(SlopGuard::InvalidInput, /usage/)
    report['runs'].first['input_tokens'] = 100
    report['metrics']['by_rule']['G1']['misses'] = '<script>'
    expect { summarize }.to raise_error(SlopGuard::InvalidInput, /counts/)
  end

  it 'escapes report-controlled version text in the workflow summary' do
    report['versions']['model'] = '<script>@reviewer</script>'
    expect(summarize.markdown).to include('&lt;script&gt;')
    expect(summarize.markdown).not_to include('<script>', '@reviewer')
  end

  it 'fails clearly when the command has no report or malformed JSON' do
    Dir.mktmpdir do |directory|
      stdout, _, status = Open3.capture3(RbConfig.ruby, 'script/evaluation_summary.rb', directory, '2',
                                         chdir: SlopGuard::ROOT)
      expect(status.exitstatus).to eq(2)
      expect(stdout).to include('REPORT UNAVAILABLE', 'exactly one report')
      FileUtils.mkdir_p(File.join(directory, 'run'))
      File.write(File.join(directory, 'run/report.json'), '{')
      stdout, _, status = Open3.capture3(RbConfig.ruby, 'script/evaluation_summary.rb', directory, '2',
                                         chdir: SlopGuard::ROOT)
      expect(status.exitstatus).to eq(2)
      expect(stdout).to include('REPORT UNAVAILABLE')
    end
  end
end
