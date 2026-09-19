# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe 'local commands' do
  def run_command(*arguments)
    Open3.capture3({ 'TYPESAFE_API_KEY' => '' }, RbConfig.ruby, *arguments, chdir: SlopGuard::ROOT)
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
