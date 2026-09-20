# frozen_string_literal: true

require_relative 'lib/slop_guard/service'

# Puma loads this file in its own process, so the environment is read and validated here as well as in the
# supervisor. The worker opens the same database from bin/app-worker.
config = SlopGuard::Service::Settings.from_env
store = SlopGuard::Service::Store.open(File.join(config.data_dir, 'app.sqlite3'),
                                       identity: [config.app_id, config.installation_id, config.repository_id])
run SlopGuard::Service::Webhook.new(settings: config, store: store)
