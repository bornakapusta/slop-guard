# frozen_string_literal: true

require_relative '../../support/service'
require 'webmock/rspec'

RSpec.describe SlopGuard::Service::GitHubClient do
  include_context 'app service'
  let(:api) { described_class.new(settings) }
  let(:token_url) { 'https://api.github.com/app/installations/7/access_tokens' }
  let(:pull_url) { 'https://api.github.com/repos/owner/demo/pulls/1' }
  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }

  before do
    allow(settings).to receive(:private_key).and_return(private_key)
    stub_request(:post,
                 token_url).to_return(body: JSON.generate(token: 'test-token', expires_at: (Time.now + 3600).iso8601))
  end

  it 'authenticates as the App and limits tokens to the configured repository and permissions' do
    headers = { 'Authorization' => 'Bearer test-token', 'X-Github-Api-Version' => '2026-03-10' }
    stub_request(:get, pull_url).with(headers: headers).to_return(body: '{"number":1}')
    expect(api.get('/repos/owner/demo/pulls/1')).to eq('number' => 1)
    expect(WebMock).to(have_requested(:post, token_url).with do |request|
      token = request.headers.fetch('Authorization').delete_prefix('Bearer ')
      claims, = JWT.decode(token, private_key.public_key, true, algorithm: 'RS256')
      data = JSON.parse(request.body)
      claims['iss'] == '8' && claims['exp'] - claims['iat'] <= 600 && data == {
        'repository_ids' => [42], 'permissions' => { 'contents' => 'read', 'pull_requests' => 'write' }
      }
    end)
  end

  it 'does not forward credentials to a redirect destination' do
    stub_request(:get, pull_url).to_return(status: 302, headers: { 'Location' => 'https://elsewhere.example/collect' })
    expect { api.get('/repos/owner/demo/pulls/1') }.to raise_error(described_class::Failure)
    expect(WebMock).not_to have_requested(:any, /elsewhere/)
  end

  it 'does not automatically retry an ambiguous write' do
    stub_request(:post, pull_url).to_timeout
    expect { api.post('/repos/owner/demo/pulls/1', body: 'test') }.to raise_error(described_class::Failure)
    expect(WebMock).to have_requested(:post, pull_url).once
  end

  it 'honors rate-limit retry timing and omits response bodies from errors' do
    stub_request(:get, pull_url).to_return(status: 429, headers: { 'Retry-After' => '120' }, body: 'sensitive')
    expect { api.get('/repos/owner/demo/pulls/1') }.to raise_error(described_class::Failure) do |error|
      expect(error.delay).to eq(120)
      expect(error.message).not_to include('sensitive')
    end
  end

  it 'reads all collection pages before returning evidence' do
    stub_request(:get, "#{pull_url}/files?per_page=100&page=1").to_return(body: JSON.generate(Array.new(100) { {} }))
    stub_request(:get, "#{pull_url}/files?per_page=100&page=2").to_return(body: '[{"filename":"last.rb"}]')
    expect(api.list('/repos/owner/demo/pulls/1/files').size).to eq(101)
  end

  it 'bounds response bodies' do
    stub_request(:get, pull_url).to_return(body: 'x' * ((4 * 1024 * 1024) + 1))
    expect { api.get('/repos/owner/demo/pulls/1') }.to raise_error(SlopGuard::LimitExceeded)
  end
end
