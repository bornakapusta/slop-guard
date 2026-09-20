# frozen_string_literal: true

require_relative '../../support/service'

RSpec.describe SlopGuard::Service::GitHubSource do
  include_context 'app service'
  let(:source) { described_class.new(client: client, settings: settings, profile: ruby_profile) }
  let(:ancestor) { 'c' * 40 }
  let(:tree_entries) do
    [{ 'path' => 'lib/parser.rb', 'type' => 'blob', 'mode' => '100644', 'size' => 30, 'sha' => 'd' * 40 },
     { 'path' => 'spec/spec_helper.rb', 'type' => 'blob', 'mode' => '100644', 'size' => 0, 'sha' => 'e' * 40 }]
  end

  before do
    allow(client).to receive(:get).with('/repos/owner/demo/pulls/1') { pull }
    allow(client).to receive(:get).with("/repos/owner/demo/compare/#{base}...#{head}")
                                  .and_return('merge_base_commit' => { 'sha' => ancestor })
    allow(client).to receive(:list).with('/repos/owner/demo/pulls/1/files')
                                   .and_return([{ 'filename' => 'lib/parser.rb' }])
    allow(client).to receive(:get).with("/repos/owner/demo/git/trees/#{ancestor}?recursive=1")
                                  .and_return('truncated' => false, 'tree' => tree_entries.drop(1))
    allow(client).to receive(:get).with("/repos/owner/demo/git/trees/#{head}?recursive=1")
                                  .and_return('truncated' => false, 'tree' => tree_entries)
    allow(client).to receive(:get).with("/repos/owner/demo/git/blobs/#{'d' * 40}")
                                  .and_return('encoding' => 'base64',
                                              'content' => Base64.strict_encode64("class Parser\nend\n"))
    allow(client).to receive(:get).with("/repos/owner/demo/git/blobs/#{'e' * 40}")
                                  .and_return('encoding' => 'base64', 'content' => '')
  end

  it 'collects the immutable merge-base and head trees into the existing snapshot engine' do
    snapshot = source.snapshot(pull)
    expect(snapshot.changed['lib/parser.rb']).to eq([1, 2])
    expect(snapshot.files['lib/parser.rb']).to eq("class Parser\nend\n")
    expect(snapshot.gaps).to be_empty
  end

  it 'rejects truncated trees rather than treating omitted code as reviewed' do
    allow(client).to receive(:get).with("/repos/owner/demo/git/trees/#{head}?recursive=1")
                                  .and_return('truncated' => true, 'tree' => [])
    expect { source.snapshot(pull) }.to raise_error(SlopGuard::LimitExceeded, /truncated/)
  end

  it 'rejects incomplete PR file inventories' do
    pull['changed_files'] = 2
    expect { source.snapshot(pull) }.to raise_error(SlopGuard::InputTooLarge, /inventory/)
  end

  it 'rejects evidence collected across two PR revisions' do
    allow(client).to receive(:get).with('/repos/owner/demo/pulls/1').and_return(pull.merge('body' => 'edited'))
    expect { source.snapshot(pull) }.to raise_error(SlopGuard::Service::StaleReview)
  end

  it 'reports symlinks as evidence gaps and never reads their targets' do
    tree_entries.first['mode'] = '120000'
    expect(source.snapshot(pull).gaps.join).to include('Non-regular file')
    expect(client).not_to have_received(:get).with("/repos/owner/demo/git/blobs/#{'d' * 40}")
  end

  it 'bounds blobs before issuing provider requests' do
    tree_entries.first['size'] = 16_385
    expect { source.snapshot(pull) }.to raise_error(SlopGuard::InputTooLarge, /16 KiB/)
  end

  it 'does not accept repository or SHA values from an unexpected source' do
    pull['base']['repo']['id'] = 99
    expect { source.pull(1) }.to raise_error(SlopGuard::InvalidInput, /identity/)
    pull['base']['repo']['id'] = 42
    pull['head']['sha'] = '../../elsewhere'
    expect { source.pull(1) }.to raise_error(SlopGuard::InvalidInput, /object ID/)
  end
end
