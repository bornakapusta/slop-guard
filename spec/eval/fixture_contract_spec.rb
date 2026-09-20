# frozen_string_literal: true

RSpec.describe SlopGuard::Dataset do
  subject(:dataset) { described_class.new(File.join(SlopGuard::ROOT, 'eval')) }

  it 'validates all four rules across 16 development and 8 held-out cases' do
    expect(dataset.validate!).to be(true)
    expect(dataset.cases('development').size).to eq(16)
    expect(dataset.cases('holdout').size).to eq(8)
  end

  it 'keeps every ordinary case within the state budget without omitting tests' do
    dataset.cases.reject { |entry| entry['id'].end_with?('incomplete') }.each do |entry|
      snapshot = demo_snapshot(dataset.input(entry['id']))
      expect(snapshot.gaps).to eq([]), entry['id']
      expect(JSON.generate(snapshot.state).bytesize).to be < 27 * 1024
    end
  end

  it 'reports an unknown case ID the same way for review input and labels' do
    expect { dataset.input('no-such-case') }.to raise_error(SlopGuard::InvalidInput, 'Unknown case ID')
    expect { dataset.labels('no-such-case') }.to raise_error(SlopGuard::InvalidInput, 'Unknown case ID')
  end

  it 'does not put labels or split metadata into review input' do
    input = dataset.input('g1-violation')
    expect(input.keys.sort).to eq(%w[before files omitted pr_body])
    expect(JSON.generate(input)).not_to include('authored_before_model_calls', 'forbidden_findings', 'rationale')
  end

  it 'rejects traversal and symlinks' do
    expect { dataset.safe_path('../secrets') }.to raise_error(SlopGuard::InvalidInput)
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, 'manifest.json'), '{"cases":[]}')
      File.symlink('/etc', File.join(directory, 'outside'))
      local = described_class.new(directory)
      expect { local.safe_path('outside/passwd') }.to raise_error(SlopGuard::InvalidInput)
    end
  end

  it 'rejects invalid anchors, preimages, and families shared across splits' do
    Dir.mktmpdir do |directory|
      FileUtils.cp_r("#{dataset.root}/.", directory)
      local = described_class.new(directory)
      local.manifest['cases'].last['family'] = local.cases.first['family']
      expect { local.validate! }.to raise_error(SlopGuard::InvalidInput, /crosses/)
      local = described_class.new(directory)
      path = File.join(directory, local.cases.first['labels'])
      labels = JSON.parse(File.read(path))
      labels['findings'].first['anchors'].first['line'] = 9000
      File.write(path, JSON.generate(labels))
      expect { local.validate! }.to raise_error(SlopGuard::InvalidInput, /anchor/)
      entry = local.cases.first
      path = File.join(directory, entry['input'])
      data = JSON.parse(File.read(path))
      data['changes'].values.first['before_sha256'] = 'wrong'
      File.write(path, JSON.generate(data))
      expect { local.input(entry['id']) }.to raise_error(SlopGuard::InvalidInput, /preimage/)
    end
  end
end
