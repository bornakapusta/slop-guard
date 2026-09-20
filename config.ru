# frozen_string_literal: true

require_relative 'lib/slop_guard/service'

config = SlopGuard::Service::Settings.new
store = SlopGuard::Service::Store.new(File.join(config.data_dir, 'app.sqlite3'),
                                      identity: [config.app_id, config.installation_id, config.repository_id])
run SlopGuard::Service::Webhook.new(settings: config, store: store)
