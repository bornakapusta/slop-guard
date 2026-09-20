# frozen_string_literal: true

require_relative '../../support/service'
require 'rack/test'

RSpec.describe SlopGuard::Service::Webhook do
  include Rack::Test::Methods

  include_context 'app service'

  let(:app) { described_class.new(settings: settings, store: store) }
  let(:payload) do
    { 'action' => 'opened', 'number' => 1, 'installation' => { 'id' => 7 }, 'repository' => { 'id' => 42 } }
  end

  def deliver(data = payload, event: 'pull_request', id: 'delivery-1', signature: nil)
    body = data.is_a?(String) ? data : JSON.generate(data)
    signature ||= "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', settings.webhook_secret, body)}"
    post '/webhooks', body, 'HTTP_X_GITHUB_EVENT' => event, 'HTTP_X_GITHUB_DELIVERY' => id,
                            'HTTP_X_HUB_SIGNATURE_256' => signature, 'CONTENT_TYPE' => 'application/json'
  end

  it 'durably enqueues a signed event and acknowledges duplicate deliveries' do
    deliver
    expect(last_response.status).to eq(202)
    deliver
    expect(last_response.status).to eq(202)
    expect(store.claim['pr']).to eq(1)
    expect(store.claim).to be_nil
  end

  it 'rejects invalid signatures without enqueuing work' do
    deliver(signature: 'sha256=forged')
    expect(last_response.status).to eq(401)
    expect(store.claim).to be_nil
  end

  it 'ignores events for another installed repository' do
    deliver(payload.merge('repository' => { 'id' => 99 }))
    expect(last_response.status).to eq(202)
    expect(store.claim).to be_nil
  end

  it 'ignores events from another installation' do
    deliver(payload.merge('installation' => { 'id' => 99 }))
    expect(store.claim).to be_nil
  end

  it 'coalesces successive deliveries for the same PR' do
    deliver
    deliver(payload.merge('action' => 'synchronize'), id: 'delivery-2')
    expect(store.claim['id']).to eq(2)
    expect(store.claim).to be_nil
  end

  it 'rejects malformed signed JSON and oversized bodies' do
    deliver('{')
    expect(last_response.status).to eq(400)
    deliver('a' * (described_class::MAX_BODY + 1))
    expect(last_response.status).to eq(413)
  end

  it 'reports storage failure instead of acknowledging an event it cannot save' do
    allow(store).to receive(:receive).and_raise(SQLite3::BusyException)
    deliver
    expect(last_response.status).to eq(503)
  end

  it 'disables work after installation suspension' do
    deliver(payload.merge('action' => 'suspend'), event: 'installation')
    expect(last_response.status).to eq(202)
    expect(store.enabled?).to be(false)
  end

  it 'disables work when the configured repository is removed' do
    deliver(payload.merge('action' => 'removed', 'repositories_removed' => [{ 'id' => 42 }]),
            event: 'installation_repositories')
    expect(last_response.status).to eq(202)
    expect(store.enabled?).to be(false)
  end

  it 'exposes a credential-free health response' do
    get '/healthz'
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to eq('status' => 'ok')
  end
end
