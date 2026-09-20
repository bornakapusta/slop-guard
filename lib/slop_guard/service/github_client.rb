# frozen_string_literal: true

require 'jwt'
require 'net/http'
require 'timeout'

module SlopGuard
  module Service
    # A fixed-host REST client. Writes are never retried inside the HTTP layer.
    class GitHubClient
      # Carries only a status and retry delay, never a potentially sensitive response body.
      class Failure < Error
        attr_reader :status, :delay

        def initialize(status = nil, delay: 60)
          @status = status
          @delay = delay
          super(status ? "GitHub request failed (HTTP #{status})" : 'GitHub request outcome is unknown')
        end

        def retryable?
          status.nil? || [401, 403, 429, 500, 502, 503, 504].include?(status)
        end
      end

      def initialize(settings)
        @settings = settings
      end

      def repo_path
        "/repos/#{@settings.repository}"
      end

      def get(path)
        request(:get, path)
      end

      def post(path, data)
        request(:post, path, data)
      end

      def patch(path, data)
        request(:patch, path, data)
      end

      def list(path)
        result = []
        10.times do |index|
          page = get("#{path}?per_page=100&page=#{index + 1}")
          raise InvalidInput, 'Invalid GitHub collection' unless page.is_a?(Array)

          result.concat(page)
          return result if page.size < 100
        end
        raise LimitExceeded, 'GitHub collection exceeds 1,000 entries'
      end

      def bot_login
        @bot_login ||= "#{request(:get, '/app', nil, token: jwt).fetch('slug')}[bot]"
      end

      private

      def jwt
        JWT.encode({ iat: Time.now.to_i - 60, exp: Time.now.to_i + 540, iss: @settings.app_id.to_s },
                   @settings.private_key, 'RS256')
      end

      def installation_token
        return @token if @token && @expires_at > Time.now + 60

        result = request(:post, "/app/installations/#{@settings.installation_id}/access_tokens",
                         { repository_ids: [@settings.repository_id],
                           permissions: { contents: 'read', pull_requests: 'write' } }, token: jwt)
        @expires_at = Time.parse(result.fetch('expires_at'))
        @token = result.fetch('token')
      end

      def request(method, path, data = nil, token: nil)
        unless path.start_with?('/repos/', '/app') && !path.match?(/[\r\n#]/)
          raise InvalidInput, 'Invalid GitHub API path'
        end

        token ||= installation_token
        uri = URI("https://api.github.com#{path}")
        request = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method).new(uri)
        request['Authorization'] = "Bearer #{token}"
        request['Accept'] = 'application/vnd.github+json'
        request['X-GitHub-Api-Version'] = '2026-03-10'
        request['User-Agent'] = 'slop-guard'
        request['Content-Type'] = 'application/json'
        request.body = JSON.generate(data) if data
        response, body = exchange(uri, request)
        unless response.code.to_i.between?(200, 299)
          @token = nil if response.code == '401'
          delay = [response['retry-after'].to_i, response['x-ratelimit-reset'].to_i - Time.now.to_i, 60].max
          raise Failure.new(response.code.to_i, delay: delay)
        end
        JSON.parse(body)
      rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, JSON::ParserError
        raise Failure
      end

      def exchange(uri, request)
        body = +''
        response = nil
        Timeout.timeout(20) do
          Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10,
                                              write_timeout: 10) do |http|
            http.max_retries = 0
            http.request(request) do |reply|
              response = reply
              reply.read_body do |chunk|
                body << chunk
                raise LimitExceeded, 'GitHub response exceeds 4 MiB' if body.bytesize > 4 * 1024 * 1024
              end
            end
          end
        end
        [response, body]
      end
    end
  end
end
