# frozen_string_literal: true

module SlopGuard
  module Service
    class Publisher
      # Shared context of one delivery to one pull request head. `current` re-checks that the pull request is
      # still the reviewed revision and is called before every write; an intent is stored before any create.
      class Delivery
        def initialize(client:, store:, number:, head:, run_id:, report:, changed:, current:)
          @client = client
          @store = store
          @number = number
          @head = head
          @run_id = run_id
          @report = report
          @changed = changed
          @current = current
        end

        private

        attr_reader :client, :store, :number, :head, :run_id, :report, :changed, :current

        def owned?(comment)
          comment.dig('user', 'type') == 'Bot' && comment.dig('user', 'login') == client.bot_login
        end

        def source_url
          "https://github.com/#{client.repo_path.delete_prefix('/repos/')}/blob/#{head}"
        end

        # Stores the intent, creates, and confirms. A definitive rejection clears the intent so a retry may create;
        # an unknown outcome keeps it so a retry raises PublicationUncertain instead of duplicating.
        def create(key)
          store.intend(key)
          created = yield
          store.confirmed(key, created.fetch('id'))
          created
        rescue GitHubClient::Failure => e
          store.clear_intent(key) if definitive_rejection?(e)
          raise
        end

        def definitive_rejection?(error)
          [400, 401, 403, 404, 422, 429].include?(error.status)
        end
      end
    end
  end
end
