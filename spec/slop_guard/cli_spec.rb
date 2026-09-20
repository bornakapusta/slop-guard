# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'stringio'

RSpec.describe SlopGuard::CLI do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:stdin) { StringIO.new }
  let(:env) { { 'TYPESAFE_API_KEY' => '' } }

  def run(*argv)
    described_class.new(stdout: stdout, stderr: stderr, stdin: stdin, env: env).run(argv)
  end

  it 'inspects a saved case as JSON without credentials or label leakage' do
    expect(run('g1-legitimate', '--inspect')).to eq(0)
    expect(stderr.string).to eq('')
    output = JSON.parse(stdout.string)
    expect(output['gaps']).to eq([])
    expect(output['profile']['name']).to eq('demo')
    expect(output['rules_files']).to include('config/rules/g1.yml')
    expect(output['evidence']).to have_key('head')
    expect(stdout.string).not_to include('forbidden_findings', 'rationale')
  end

  it 'shows the resolved profile and rule definitions offline' do
    expect(run('--show-rules', '--profile', 'ruby')).to eq(0)
    output = JSON.parse(stdout.string)
    expect(output['profile']['rules_dir']).to eq('config/rules/ruby')
    expect(output['definitions'].keys).to eq(%w[G1 G2 G3 G4])
    expect(output['rules_revision']).to eq(SlopGuard::Rules.load(ruby_profile.rules_dir).revision)
  end

  it 'reviews an arbitrary input document with expectations from stdin' do
    input = fixture_dataset.input('g1-fixed')
    stdin.string = input.delete('pr_body')
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'input.json')
      File.write(path, JSON.generate(input))
      expect(run('--input', path, '--expectations', '-', '--profile', 'demo', '--inspect')).to eq(0)
      expect(JSON.parse(stdout.string)['expectation_gaps']).to eq([])
    end
  end

  it 'exits 2 for invalid input and usage, as prose or as a JSON error envelope' do
    expect(run('unknown', '--inspect')).to eq(2)
    expect(stderr.string).to include('Unknown case ID')
    stdout.string = +''
    expect(run('unknown', '--inspect', '--json')).to eq(2)
    error = JSON.parse(stdout.string).fetch('error')
    expect(error.values_at('class', 'exit_status')).to eq(['InvalidInput', 2])
    expect(run('g1-fixed', '--inspect', '--live')).to eq(2)
    expect(stderr.string).to include('Usage:')
    expect(run('g1-fixed', '--live', '--env-file', File.join(Dir.mktmpdir, 'absent.env'))).to eq(2)
    expect(stderr.string).to include('Credential file does not exist')
  end

  it 'never reads a credential file unless one is named, and exits 3 without credentials' do
    env.delete('TYPESAFE_API_KEY')
    expect(run('g1-fixed', '--live')).to eq(3)
    expect(stderr.string.strip).to eq('TYPESAFE_API_KEY is not configured')
  end

  it 'maps review status to exit codes and reports where the report and ledger were written' do
    env['TYPESAFE_API_KEY'] = 'test-key'
    statuses = %w[complete incomplete failed]
    codes = statuses.map do |status|
      report = { 'status' => status, 'snapshot' => 'abc', 'rules' => {} }
      allow(SlopGuard::Evaluator).to receive(:new).and_return(instance_double(SlopGuard::Evaluator, call: report))
      Dir.mktmpdir do |directory|
        stdout.string = +''
        code = run('g1-fixed', '--live', '--json', '--output', directory)
        output = JSON.parse(stdout.string)
        expect(output['report_path']).to start_with(directory)
        expect(File).to exist(output['report_path'])
        expect(output['ledger_path']).to end_with('requests.jsonl')
        code
      end
    end
    expect(codes).to eq([0, 1, 3])
  end
end

RSpec.describe 'local commands' do
  def run_command(*)
    Open3.capture3({ 'TYPESAFE_API_KEY' => '' }, RbConfig.ruby, *, chdir: SlopGuard::ROOT)
  end

  it 'wires bin/review to the CLI class' do
    stdout, stderr, status = run_command('bin/review', 'g1-legitimate', '--inspect')
    expect(status.exitstatus).to eq(0), stderr
    expect(JSON.parse(stdout)['gaps']).to eq([])
  end

  it 'analyzes saved evidence offline' do
    client = stub_client { |_state, questions| questions.transform_values { 0.5 } }
    Dir.mktmpdir do |directory|
      runner = SlopGuard::EvalRunner.new(dataset: fixture_dataset)
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
  end

  it 'validates fixtures offline, rejects conflicting evaluate modes and a missing credential file' do
    stdout, stderr, status = run_command('bin/evaluate', '--validate')
    expect(status.exitstatus).to eq(0), stderr
    expect(JSON.parse(stdout)['cases'].size).to eq(24)
    _, stderr, status = run_command('bin/evaluate', '--validate', '--live')
    expect(status.exitstatus).to eq(2)
    expect(stderr).to include('Usage:')
    _, stderr, status = run_command('bin/evaluate', '--live', '--env-file', File.join(Dir.mktmpdir, 'absent.env'))
    expect(status.exitstatus).to eq(2)
    expect(stderr).to include('Credential file does not exist')
  end
end
