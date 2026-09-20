# frozen_string_literal: true

require_relative '../../support/service'
require 'rack/builder'
require 'rack/mock'

RSpec.describe 'config.ru' do
  def with_env(values)
    previous = values.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  it 'boots the webhook receiver from a validated environment' do
    Dir.mktmpdir('slop-guard-rackup') do |directory|
      key_path = File.join(directory, 'app.pem')
      File.write(key_path, OpenSSL::PKey::RSA.new(2048).to_pem)
      env = { 'GITHUB_APP_ID' => '8', 'GITHUB_INSTALLATION_ID' => '7', 'GITHUB_REPOSITORY_ID' => '42',
              'GITHUB_REPOSITORY' => 'owner/demo', 'GITHUB_PRIVATE_KEY_PATH' => key_path,
              'GITHUB_WEBHOOK_SECRET' => 's' * 32, 'TYPESAFE_API_KEY' => 'test-key',
              'SLOP_GUARD_DATA_DIR' => File.join(directory, 'data') }
      app = with_env(env) { Rack::Builder.parse_file(File.join(SlopGuard::ROOT, 'config.ru')) }
      response = Rack::MockRequest.new(app).get('/healthz')
      expect(response.status).to eq(200)
      expect(File).to exist(File.join(directory, 'data', 'app.sqlite3'))
    end
  end
end
