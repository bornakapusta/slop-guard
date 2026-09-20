# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe 'local commands' do
  def run_command(*)
    Open3.capture3({ 'TYPESAFE_API_KEY' => '' }, RbConfig.ruby, *, chdir: SlopGuard::ROOT)
  end

  it 'inspects evidence as JSON without credentials or label leakage' do
    stdout, stderr, status = run_command('bin/review', 'g1-legitimate', '--inspect')
    expect(status.exitstatus).to eq(0)
    expect(stderr).to eq('')
    output = JSON.parse(stdout)
    expect(output['gaps']).to eq([])
    expect(output['evidence']).to have_key('head')
    expect(stdout).not_to include('forbidden_findings', 'rationale')
  end

  it 'analyzes saved evidence offline and rejects an invalid benchmark invocation' do
    client = Object.new
    client.define_singleton_method(:ask) { |_state, questions| questions.transform_values { 0.5 } }
    Dir.mktmpdir do |directory|
      runner = SlopGuard::EvalRunner.new(dataset: SlopGuard::Dataset.new(File.join(SlopGuard::ROOT, 'eval')))
      runner.run(split: 'development', repetitions: 1, directory: directory, client_factory: ->(_) { client })
      path = File.join(directory, 'report.json')
      stdout, stderr, status = run_command('bin/analyze-evaluation', path, '--json')
      expect(status.exitstatus).to eq(0)
      expect(stderr).to eq('')
      metrics = JSON.parse(stdout)
      expect(metrics.values_at('live', 'labels_reviewed', 'distinct_cases',
                               'observed_reviews')).to eq([false, false, 16, 16])
      expect(metrics['by_rule']['G1']['mean_case_repeat_agreement']).to be_nil
      File.write(path, '{}')
      _, _, status = run_command('bin/analyze-evaluation', path)
      expect(status.exitstatus).to eq(2)
    end
    _, stderr, status = run_command('bin/evaluate', '--validate', '--benchmark')
    expect(status.exitstatus).to eq(2)
    expect(stderr).to include('--benchmark requires --live --split development')
  end

  it 'rejects unknown cases, missing credentials and conflicting modes clearly' do
    _, stderr, status = run_command('bin/review', 'unknown', '--inspect')
    expect(status.exitstatus).to eq(2)
    expect(stderr).to include('Unknown case ID')
    _, stderr, status = run_command('bin/review', 'g1-fixed', '--live')
    expect(status.exitstatus).to eq(2)
    expect(stderr).to include('TYPESAFE_API_KEY is not configured')
    _, stderr, status = run_command('bin/evaluate', '--validate', '--live')
    expect(status.exitstatus).to eq(2)
    expect(stderr).to include('Usage:')
  end
end
