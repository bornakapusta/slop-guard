# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe SlopGuard::GitSource do
  let(:body) { "## Expected behavior\n- [double] Calculator.double(2) returns 4.\n\n## Failure cases\n" }
  let(:original) { "class Calculator\n  def self.double(number)\n    number\n  end\nend\n" }
  let(:updated) { original.sub('    number', '    number * 2') }

  around do |example|
    Dir.mktmpdir('slop-guard-repo-') do |path|
      @repository = path
      git('init', '-b', 'main')
      git('config', 'user.email', 'test@example.invalid')
      git('config', 'user.name', 'Slop Guard test')
      write('lib/calculator.rb', original)
      write('spec/spec_helper.rb', "require 'rspec'\n")
      write('spec/calculator_spec.rb',
            "RSpec.describe Calculator do\n  it('doubles') { expect(Calculator.double(2)).to eq(4) }\nend\n")
      git('add', '.')
      git('commit', '-m', 'Baseline')
      git('checkout', '-b', 'feature')
      write('lib/calculator.rb', updated)
      git('add', '.')
      git('commit', '-m', 'Double the number')
      example.run
    end
  end

  def git(*)
    stdout, stderr, status = Open3.capture3('git', '-C', @repository, *)
    raise stderr unless status.success?

    stdout.strip
  end

  def write(path, text)
    target = File.join(@repository, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, text)
  end

  def source(base: 'main', head: 'feature')
    described_class.new(repository: @repository, base: base, head: head)
  end

  it 'uses the merge base and excludes base-only, staged, unstaged and untracked changes' do
    base = git('rev-parse', 'main')
    git('checkout', 'main')
    write('lib/base_only.rb', 'class BaseOnly; end')
    git('add', '.')
    git('commit', '-m', 'Unrelated base change')
    git('checkout', 'feature')
    write('lib/calculator.rb', 'staged content')
    git('add', '.')
    write('lib/calculator.rb', 'unstaged content')
    write('lib/untracked.rb', 'untracked content')
    adapter = source
    input = adapter.input(pr_body: body)
    expect(input['before']['lib/calculator.rb']).to eq(original)
    expect(input['files']['lib/calculator.rb']).to eq(updated)
    expect(input['files']).not_to have_key('lib/base_only.rb')
    expect(input['files']).not_to have_key('lib/untracked.rb')
    expect(adapter.metadata['merge_base']).to eq(base)
    expect(adapter.metadata['base']).not_to eq(base)
    expect(git('status', '--porcelain')).to include('MM lib/calculator.rb', '?? lib/untracked.rb')
  end

  it 'preserves additions, deletions and renames without modifying the working tree' do
    git('mv', 'lib/calculator.rb', 'lib/renamed.rb')
    write('lib/added.rb', 'class Added; end')
    git('add', '.')
    git('commit', '-m', 'Rename and add')
    input = source.input(pr_body: body)
    expect(input['before']).to have_key('lib/calculator.rb')
    expect(input['files']).not_to have_key('lib/calculator.rb')
    expect(input['files']['lib/renamed.rb']).to eq(updated)
    expect(input['files']).to have_key('lib/added.rb')
    expect(git('status', '--porcelain')).to eq('')
  end

  it 'does not execute source, follow symlinks or include credentials and unsupported paths' do
    marker = File.join(@repository, 'executed')
    write('lib/danger.rb', "File.write(#{marker.inspect}, 'executed')\n")
    write('.env', 'SECRET=never-send-this')
    write('README.md', 'Documentation')
    File.symlink('/etc/passwd', File.join(@repository, 'lib/link.rb'))
    git('add', '.')
    git('commit', '-m', 'Add untrusted inputs')
    adapter = source
    snapshot = SlopGuard::Snapshot.new(adapter.input(pr_body: body), profile: adapter.profile)
    expect(File).not_to exist(marker)
    expect(snapshot.files).not_to have_key('lib/link.rb')
    expect(snapshot.skipped).to include('.env', 'README.md')
    expect(snapshot.state.to_json).not_to include('never-send-this')
    expect(snapshot.gaps).to include('Non-regular file was not inspected: lib/link.rb')
    client = instance_double(SlopGuard::JevClient)
    expect(client).not_to receive(:ask)
    result = SlopGuard::Evaluator.new(client: client).call(snapshot)
    expect(result['status']).to eq('incomplete')
  end

  it 'keeps unsupported-only changes visible without inventing a Ruby change' do
    git('checkout', 'main')
    write('README.md', 'Only docs changed')
    git('add', '.')
    git('commit', '-m', 'Documentation')
    adapter = source(base: 'feature', head: 'main')
    snapshot = SlopGuard::Snapshot.new(adapter.input(pr_body: body), profile: adapter.profile)
    expect(snapshot.changed).to eq({})
    expect(snapshot.skipped).to include('README.md')
  end

  it 'rejects invalid refs, option injection, unrelated history and oversized files' do
    expect { source(base: '--help').input(pr_body: body) }.to raise_error(SlopGuard::InvalidInput)
    expect { source(base: 'missing').input(pr_body: body) }.to raise_error(SlopGuard::InvalidInput, /rev-parse failed/)
    write('lib/large.rb', 'x' * 16_385)
    git('add', '.')
    git('commit', '-m', 'Oversized file')
    expect { source.input(pr_body: body) }.to raise_error(SlopGuard::LimitExceeded, /16 KiB/)
    git('checkout', '--orphan', 'unrelated')
    git('commit', '-m', 'Unrelated root')
    expect do
      source(head: 'unrelated').input(pr_body: body)
    end.to raise_error(SlopGuard::InvalidInput, /merge-base failed/)
  end

  it 'rejects binary input and a repository above the file limit' do
    write('lib/binary.rb', "invalid\x00source")
    git('add', '.')
    git('commit', '-m', 'Binary Ruby')
    expect { source.input(pr_body: body) }.to raise_error(SlopGuard::InvalidInput, /UTF-8 text/)
    git('rm', 'lib/binary.rb')
    101.times { |index| write("lib/file_#{index}.rb", '') }
    git('add', '.')
    git('commit', '-m', 'Too many files')
    expect { source.input(pr_body: body) }.to raise_error(SlopGuard::LimitExceeded, /100 supported files/)
  end

  it 'runs the CLI inspection without credentials and identifies committed revisions and rule profile' do
    expectations = File.join(@repository, 'expectations.md')
    File.write(expectations, body)
    command = [RbConfig.ruby, File.join(SlopGuard::ROOT, 'bin/review'), '--repo', @repository,
               '--base', 'main', '--expectations', expectations, '--inspect']
    stdout, stderr, status = Open3.capture3({ 'TYPESAFE_API_KEY' => '' }, *command)
    expect(status.exitstatus).to eq(0), stderr
    output = JSON.parse(stdout)
    expect(output['gaps']).to eq([])
    expect(output['source']['head']).to eq(git('rev-parse', 'HEAD'))
    expect(output['evidence']['changed_lines']['lib/calculator.rb']).to include(3)
    expect(output['rules_revision']).to eq(SlopGuard::Rules.new(repository: true).revision)
    expect(output['rules_revision']).not_to eq(SlopGuard::Rules.new.revision)
    _, stderr, status = Open3.capture3(*command, '--live')
    expect(status.exitstatus).to eq(2)
    expect(stderr).to include('Usage:')
  end

  it 'reviews a real Git snapshot offline using a stubbed model through the existing evaluator' do
    adapter = source
    snapshot = SlopGuard::Snapshot.new(adapter.input(pr_body: body), profile: adapter.profile)
    client = instance_double(SlopGuard::JevClient)
    allow(client).to receive(:ask) { |_state, questions| questions.transform_values { 0.5 } }
    result = SlopGuard::Evaluator.new(client: client, rules: SlopGuard::Rules.new(repository: true)).call(snapshot)
    expect(client).to have_received(:ask).at_least(:once)
    expect(result['rules']['G1']['outcome']).to eq('inconclusive')
    expect(result['rules']['G1']['readings']).not_to be_empty
    expect(SlopGuard::Report.markdown(result)).to include('G1: inconclusive')
  end
  it 'keeps coverage gaps inconclusive even when no supported source lines changed' do
    File.symlink('/etc/passwd', File.join(@repository, 'lib/link.rb'))
    git('add', '.')
    git('commit', '-m', 'Only a symlink')
    adapter = source(base: 'HEAD~1')
    snapshot = SlopGuard::Snapshot.new(adapter.input(pr_body: body), profile: adapter.profile)
    expect(snapshot.changed).to eq({})
    client = instance_double(SlopGuard::JevClient)
    expect(client).not_to receive(:ask)
    result = SlopGuard::Evaluator.new(client: client).call(snapshot)
    expect(result['status']).to eq('incomplete')
    expect(result['rules'].values.map { |rule| rule['outcome'] }.uniq).to eq(['inconclusive'])
  end

  it 'accepts explicit trusted custom rules and reports malformed rules without a backtrace' do
    expectations = File.join(@repository, 'expectations.md')
    File.write(expectations, body)
    command = [RbConfig.ruby, File.join(SlopGuard::ROOT, 'bin/review'), '--repo', @repository,
               '--base', 'main', '--expectations', expectations, '--inspect', '--rules-dir']
    stdout, stderr, status = Open3.capture3(*command, File.join(SlopGuard::ROOT, 'config/rules'))
    expect(status.exitstatus).to eq(0), stderr
    expect(JSON.parse(stdout)['rules_revision']).to eq(SlopGuard::Rules.new.revision)
    write('rules/g1.yml', 'low: invalid')
    _, stderr, status = Open3.capture3(*command, File.join(@repository, 'rules'))
    expect(status.exitstatus).to eq(2)
    expect(stderr).to start_with('Invalid rule configuration')
    expect(stderr.lines.size).to eq(1)
  end

  it 'rejects oversized expectation text and preserves refs as literal arguments' do
    expect { source.input(pr_body: 'x' * 16_385) }.to raise_error(SlopGuard::InvalidInput, /16 KiB/)
    marker = File.join(@repository, 'injected')
    expect { source(base: "$(touch #{marker})").input(pr_body: body) }.to raise_error(SlopGuard::InvalidInput)
    expect(File).not_to exist(marker)
  end
end
