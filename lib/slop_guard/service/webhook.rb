# frozen_string_literal: true

require 'sinatra/base'

module SlopGuard
  module Service
    # Verifies raw webhook bytes and acknowledges only after durable enqueue.
    class Webhook < Sinatra::Base
      set :show_exceptions, false
      set :dump_errors, false
      set :protection, except: :http_origin
      set :host_authorization, { permitted_hosts: [] }
      MAX_BODY = 1_048_576
      ACTIONS = %w[opened reopened synchronize edited ready_for_review closed converted_to_draft].freeze

      def initialize(app = nil, settings:, store:)
        super(app)
        @config = settings
        @store = store
      end

      get '/healthz' do
        halt 503 unless @store.health?
        content_type :json
        '{"status":"ok"}'
      end

      post '/webhooks' do
        body = request.body.read(MAX_BODY + 1)
        halt 413 if body.bytesize > MAX_BODY
        expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', @config.webhook_secret, body)}"
        supplied = request.env['HTTP_X_HUB_SIGNATURE_256'].to_s
        halt 401 unless supplied.bytesize == expected.bytesize && OpenSSL.fixed_length_secure_compare(supplied,
                                                                                                      expected)

        delivery = request.env['HTTP_X_GITHUB_DELIVERY'].to_s
        halt 400 unless delivery.match?(/\A[a-zA-Z0-9_-]{1,128}\z/)

        payload = JSON.parse(body)
        halt 400 unless payload.is_a?(Hash)

        event = request.env['HTTP_X_GITHUB_EVENT']
        halt 200, 'pong' if event == 'ping'
        halt 202, 'ignored' unless payload.dig('installation', 'id') == @config.installation_id

        disabled = event == 'installation' && %w[deleted suspend].include?(payload['action'])
        disabled ||= event == 'installation_repositories' && payload.fetch('repositories_removed', []).any? do |repo|
          repo['id'] == @config.repository_id
        end
        if disabled
          @store.receive(delivery, enabled: false)
        elsif event == 'pull_request' && ACTIONS.include?(payload['action']) &&
              payload.dig('repository', 'id') == @config.repository_id
          number = payload['number']
          halt 400 unless number.is_a?(Integer) && number.positive?

          @store.receive(delivery, number: number)
        end
        status 202
        'accepted'
      rescue JSON::ParserError, TypeError
        halt 400
      end

      error SQLite3::Exception do
        status 503
        'Storage unavailable; redeliver this webhook'
      end
    end
  end
end
