# frozen_string_literal: true

module SlopGuard
  module Service
    # A single worker checkpoints paid evaluation before publishing to GitHub.
    class Worker
      def initialize(settings:, store:, client:, source: nil, evaluate: nil, logger: $stdout,
                     profile: Profile.load('ruby'))
        @settings = settings
        @store = store
        @source = source || GitHubSource.new(client: client, settings: settings, profile: profile)
        @publisher = Publisher.new(client: client, store: store)
        @rules = Rules.load(profile.rules_dir)
        @evaluate = evaluate || method(:evaluate_snapshot)
        @logger = logger
      end

      def tick
        job = @store.claim
        return false unless job

        process(job)
        true
      rescue StaleReview
        @store.finish(job, 'superseded')
        # A missed webhook must not leave the newest commit unreviewed.
        @store.receive("refresh:#{job['id']}", number: job['pr']) if @store.current?(job)
        true
      rescue GitHubClient::Failure => e
        retry_job(job, e)
        true
      rescue PublicationUncertain, InvalidInput, LimitExceeded => e
        @store.finish(job, 'failed', error: e.message)
        log(job, 'failed', e.message)
        true
      rescue StandardError => e
        # Do not log response bodies, source code, credentials, or exception messages.
        @store.finish(job, 'failed', error: e.class.name) if job
        log(job, 'failed', e.class.name)
        true
      end

      private

      def process(job)
        raise StaleReview unless @store.current?(job)

        pull = @source.pull(job['pr'])
        unless pull['state'] == 'open' && !pull['draft']
          @store.finish(job, 'skipped')
          return
        end
        stamp = @source.stamp(pull)
        id = SlopGuard.digest([@settings.repository_id, job['pr'], stamp, @settings.engine_revision,
                               @rules.revision, JevClient::MODEL])
        current = lambda do
          raise StaleReview unless @store.current?(job) && @source.stamp(@source.pull(job['pr'])) == stamp
        end
        run = @store.run(id)
        unless run
          current.call
          @store.begin_run(id, job['pr'])
          run = @store.run(id)
        end
        if run['phase'] == 'prepared'
          report, changed = review(pull, current, id)
          @store.save_run(id, report, changed)
          run = @store.run(id)
        end
        if run['phase'] == 'evaluating'
          @store.save_run(id, incomplete(id, 'Review was interrupted; paid requests were not repeated'), {})
          run = @store.run(id)
        end
        unless run['phase'] == 'published'
          current.call
          @publisher.publish(number: job['pr'], head: pull.dig('head', 'sha'), run_id: id,
                             report: JSON.parse(run.fetch('report')), changed: JSON.parse(run.fetch('changed')),
                             current: current)
          @store.published(id)
        end
        @store.finish(job, 'done')
        log(job, 'done')
      end

      def review(pull, current, id)
        snapshot = @source.snapshot(pull)
        current.call
        @store.evaluating(id)
        [@evaluate.call(snapshot), snapshot.changed]
      rescue InvalidInput, LimitExceeded => e
        [incomplete(id, e.message), {}]
      rescue StaleReview, GitHubClient::Failure
        raise
      rescue StandardError => e
        [incomplete(id, "Review failed (#{e.class.name}); paid requests were not repeated"), {}]
      end

      def evaluate_snapshot(snapshot)
        budget = Budget.open(ledger: File.join(@settings.data_dir, 'budget.jsonl'))
        client = JevClient.new(api_key: @settings.typesafe_key, budget: budget)
        Evaluator.new(client: client, rules: @rules).call(snapshot)
      end

      def incomplete(id, reason)
        { 'snapshot' => id, 'status' => 'incomplete', 'rules' => @rules.definitions.to_h do |key, _|
          [key, { 'outcome' => 'inconclusive', 'findings' => [], 'gaps' => [reason] }]
        end }
      end

      def retry_job(job, error)
        state = error.retryable? && job['attempts'] < 4 ? 'pending' : 'failed'
        @store.finish(job, state, error: error.message, delay: error.delay)
        log(job, state, error.message)
      end

      def log(job, state, error = nil)
        @logger.puts(JSON.generate(job: job&.fetch('id'), number: job&.fetch('pr'), state: state, error: error))
      end
    end
  end
end
