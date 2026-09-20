# frozen_string_literal: true

require 'openssl'

module SlopGuard
  module Service
    # Explicitly limits this first deployment to one installed repository.
    class Settings
      attr_reader :app_id, :installation_id, :repository_id, :repository, :private_key,
                  :webhook_secret, :typesafe_key, :data_dir

      def initialize(env = ENV)
        @app_id = positive_id(env.fetch('GITHUB_APP_ID'))
        @installation_id = positive_id(env.fetch('GITHUB_INSTALLATION_ID'))
        @repository_id = positive_id(env.fetch('GITHUB_REPOSITORY_ID'))
        @repository = env.fetch('GITHUB_REPOSITORY')
        raise InvalidInput, 'Invalid owner/repository' unless repository.match?(%r{\A[\w.-]+/[\w.-]+\z})

        @private_key = OpenSSL::PKey::RSA.new(File.read(env.fetch('GITHUB_PRIVATE_KEY_PATH')))
        raise InvalidInput, 'An RSA private key is required' unless private_key.private?

        @webhook_secret = env.fetch('GITHUB_WEBHOOK_SECRET')
        raise InvalidInput, 'Webhook secret must be at least 32 bytes' if webhook_secret.bytesize < 32

        @typesafe_key = env.fetch('TYPESAFE_API_KEY')
        raise InvalidInput, 'TYPESAFE_API_KEY is required' if typesafe_key.empty?

        @data_dir = File.expand_path(env.fetch('SLOP_GUARD_DATA_DIR', File.join(ROOT, 'tmp/app')))
        FileUtils.mkdir_p(data_dir, mode: 0o700)
      rescue KeyError, ArgumentError, OpenSSL::PKey::PKeyError, SystemCallError
        raise InvalidInput, 'Invalid GitHub App configuration; see docs/github-app.md'
      end

      def engine_revision
        paths = Dir[File.join(ROOT, '{lib,config}/**/*'), File.join(ROOT, 'Gemfile.lock')]
        @engine_revision ||= SlopGuard.digest(paths.sort.filter_map do |path|
          [path.delete_prefix("#{ROOT}/"), File.read(path)] if File.file?(path)
        end)
      end

      private

      def positive_id(value)
        id = Integer(value, 10)
        raise InvalidInput, 'GitHub identifiers must be positive integers' unless id.positive?

        id
      end
    end
  end
end
