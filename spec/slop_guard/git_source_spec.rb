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
    described_class.new(repository: @repository, base: base, head: head, profile: ruby_profile)
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
    client = silent_client
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

  it 'rejects option-like and unknown refs, naming the Git diagnostic without mixing it into data' do
    expect { source(base: '--help').input(pr_body: body) }.to raise_error(SlopGuard::InvalidInput, /non-option/)
    expect { source(base: 'missing').input(pr_body: body) }
      .to raise_error(SlopGuard::InvalidInput, /rev-parse failed \(fatal: .*\); check repository/)
  end

  it 'rejects unrelated history and more than one merge base' do
    git('checkout', '--orphan', 'unrelated')
    git('commit', '-m', 'Unrelated root')
    expect { source(head: 'unrelated').input(pr_body: body) }
      .to raise_error(SlopGuard::InvalidInput, /merge-base failed/)
    git('checkout', 'main')
    write('lib/main_side.rb', 'class MainSide; end')
    git('add', '.')
    git('commit', '-m', 'Main side')
    main_side = git('rev-parse', 'main')
    git('checkout', 'feature')
    feature_side = git('rev-parse', 'feature')
    git('merge', '--no-edit', main_side)
    git('checkout', 'main')
    git('merge', '--no-edit', feature_side)
    expect(git('merge-base', '--all', 'main', 'feature').lines.size).to eq(2)
    expect { source.input(pr_body: body) }.to raise_error(SlopGuard::InvalidInput, /one merge base/)
  end

  it 'reports an oversized file as an evidence gap without reading it' do
    write('lib/large.rb', 'x' * 16_385)
    git('add', '.')
    git('commit', '-m', 'Oversized file')
    input = source.input(pr_body: body)
    expect(input['files']).not_to have_key('lib/large.rb')
    expect(input['source_gaps']).to include('File exceeds 16 KiB: lib/large.rb')
  end

  it 'keeps Git warnings out of parsed data when a branch and a tag share a name' do
    git('tag', 'rel', 'main')
    git('branch', 'rel', 'feature')
    adapter = source(base: 'rel')
    input = adapter.input(pr_body: body)
    expect(adapter.metadata['base']).to match(/\A\h{40}\z/)
    expect(input['files']['lib/calculator.rb']).to eq(updated)
  end

  it 'rejects tree paths containing control characters' do
    write("lib/evil\e[31m.rb", 'class Evil; end')
    git('add', '.')
    git('commit', '-m', 'Hostile path')
    expect { source.input(pr_body: body) }.to raise_error(SlopGuard::InvalidInput, /Invalid Git tree path/)
  end

  it 'records submodules as gaps, accepts executable blobs and reads each revision in one object stream' do
    commit = git('rev-parse', 'HEAD')
    File.chmod(0o755, File.join(@repository, 'lib/calculator.rb'))
    git('add', 'lib/calculator.rb')
    # A gitlink without a checkout; `git add .` would stage its removal, so commit straight from the index.
    git('update-index', '--add', '--cacheinfo', "160000,#{commit},vendor/tool")
    git('commit', '-m', 'Submodule and executable')
    expect(git('ls-tree', 'HEAD', 'lib/calculator.rb')).to start_with('100755')
    adapter = source
    calls = []
    allow(Open3).to receive(:popen3).and_wrap_original do |original, *args, **options, &block|
      calls << args.grep_v(Hash)
      original.call(*args, **options, &block)
    end
    input = adapter.input(pr_body: body)
    expect(input['files']['lib/calculator.rb']).to eq(updated)
    expect(input['source_gaps']).to include('Submodule was not inspected: vendor/tool')
    expect(calls.count { |args| args.include?('cat-file') }).to eq(2)
    expect(calls).to all(include('protocol.allow=never', 'core.fsmonitor=false'))
  end

  it 'reviews the named repository only, ignoring GIT_DIR, and refuses a subdirectory path' do
    other = Dir.mktmpdir('slop-guard-other-')
    Open3.capture3('git', '-C', other, 'init', '-q')
    begin
      ENV['GIT_DIR'] = File.join(other, '.git')
      expect(source.input(pr_body: body)['files']['lib/calculator.rb']).to eq(updated)
    ensure
      ENV.delete('GIT_DIR')
      FileUtils.remove_entry(other)
    end
    inside = described_class.new(repository: File.join(@repository, 'lib'), base: 'main', head: 'feature',
                                 profile: ruby_profile)
    expect { inside.input(pr_body: body) }.to raise_error(SlopGuard::InvalidInput, /repository root/)
  end

  it 'bounds Git output and time' do
    expect { source.send(:git, 'ls-tree', '-r', 'HEAD', limit: 8) }
      .to raise_error(SlopGuard::LimitExceeded, /byte limit/)
    stub_const('SlopGuard::GitSource::TIMEOUT_SECONDS', 0.05)
    # Stand a sleeping process in for Git so the deadline, not the command, ends the read.
    allow(Open3).to receive(:popen3).and_wrap_original do |original, env, *_command, **options, &block|
      original.call(env, 'sleep', '5', **options, &block)
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { source.send(:git, 'ls-tree', 'HEAD') }.to raise_error(SlopGuard::LimitExceeded, /timed out/)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 2
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
    expect { source.input(pr_body: body) }.to raise_error(SlopGuard::InputTooLarge, /100 supported files/)
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
    expect(output['rules_revision']).to eq(SlopGuard::Rules.new(ruby_profile.rules_dir).revision)
    expect(output['rules_revision']).not_to eq(SlopGuard::Rules.new.revision)
    _, stderr, status = Open3.capture3(*command, '--live')
    expect(status.exitstatus).to eq(2)
    expect(stderr).to include('Usage:')
  end

  it 'reviews a real Git snapshot offline using a stubbed model through the existing evaluator' do
    adapter = source
    snapshot = SlopGuard::Snapshot.new(adapter.input(pr_body: body), profile: adapter.profile)
    client = silent_client
    allow(client).to receive(:ask) { |_state, questions| questions.transform_values { 0.5 } }
    result = SlopGuard::Evaluator.new(client: client, rules: SlopGuard::Rules.new(ruby_profile.rules_dir)).call(snapshot)
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
    client = silent_client
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
