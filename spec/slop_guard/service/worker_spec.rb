# frozen_string_literal: true

require_relative '../../support/service'

RSpec.describe SlopGuard::Service::Worker do
  include_context 'app service'
  let(:source) { instance_double(SlopGuard::Service::GitHubSource, pull: pull, snapshot: snapshot) }
  let(:snapshot) { instance_double(SlopGuard::Snapshot, changed: changed) }
  let(:evaluate) { ->(_snapshot) { report } }
  let(:worker) do
    described_class.new(settings: settings, store: store, client: client, source: source, profile: ruby_profile,
                        evaluate: evaluate, logger: StringIO.new)
  end

  before do
    allow(source).to receive(:stamp) { |value| SlopGuard.digest(value) }
    allow(evaluate).to receive(:call).and_call_original
    store.receive('event-1', number: 1)
  end

  it 'reviews and publishes once across duplicate events' do
    expect(worker.tick).to be(true)
    store.receive('event-2', number: 1)
    worker.tick
    expect(evaluate).to have_received(:call).once
    expect(reviews.length).to eq(1)
    expect(summaries.length).to eq(1)
  end

  it 'does not evaluate closed or draft pull requests' do
    pull['state'] = 'closed'
    worker.tick
    expect(evaluate).not_to have_received(:call)
    expect(client).not_to have_received(:post)
  end

  it 'does not publish a result after a new commit arrives' do
    allow(evaluate).to receive(:call) do
      pull['head']['sha'] = 'c' * 40
      report
    end
    worker.tick
    expect(client).not_to have_received(:post)
    expect(store.claim).not_to be_nil
  end

  it 'retains completed evaluation when publication is retried' do
    allow(client).to receive(:post).with('/repos/owner/demo/pulls/1/reviews', anything) do |_path, data|
      reviews << { 'id' => 200, 'user' => bot, 'body' => data[:body] }
      raise SlopGuard::Service::GitHubClient::Failure.new(nil, delay: 0)
    end
    worker.tick
    worker.tick
    expect(evaluate).to have_received(:call).once
    expect(reviews.length).to eq(1)
    expect(summaries.length).to eq(1)
  end

  it 'reports an interrupted evaluation without resetting the paid budget' do
    id = SlopGuard.digest([42, 1, SlopGuard.digest(pull), settings.engine_revision,
                           SlopGuard::Rules.load(SlopGuard::Profile.load('ruby').rules_dir).revision, SlopGuard::JevClient::MODEL])
    store.begin_run(id, 1)
    store.evaluating(id)
    worker.tick
    expect(evaluate).not_to have_received(:call)
    expect(summaries.first['body']).to include('interrupted', 'inconclusive')
  end

  it 'turns evidence limits into an inconclusive report without calling Jev' do
    allow(source).to receive(:snapshot).and_raise(SlopGuard::LimitExceeded, 'Tree too large')
    worker.tick
    expect(evaluate).not_to have_received(:call)
    expect(summaries.first['body']).to include('Tree too large', 'inconclusive')
  end

  it 'reports an unexpected evaluation failure without replaying the provider' do
    allow(evaluate).to receive(:call).and_raise(JSON::ParserError, 'sensitive detail')
    worker.tick
    expect(summaries.first['body']).to include('Review failed', 'inconclusive')
    expect(summaries.first['body']).not_to include('sensitive detail')
    store.receive('another-delivery', number: 1)
    worker.tick
    expect(evaluate).to have_received(:call).once
  end

  it 'stops queued work if the installation is disabled' do
    store.receive('removed', enabled: false)
    worker.tick
    expect(evaluate).not_to have_received(:call)
    expect(client).not_to have_received(:post)
  end
end
