# frozen_string_literal: true

module SlopGuard
  module Service
    class Publisher
      # Delivers this run's findings as one pull request review with changed-line comments, or updates the threads
      # an earlier run already opened. `deliver` returns the status line the summary reports.
      class InlineReview < Delivery
        def deliver
          return 'No inline comments: this review produced no actionable findings.' if findings.empty?

          delivered = delivered_status
          return delivered if delivered

          comments, updated = comments_and_updates
          if comments.empty?
            return "#{updated} existing inline comment(s) updated. All findings are listed below." if updated.positive?

            return 'No findings could be placed on changed lines. Review their code references below.'
          end
          post(comments, updated)
        end

        private

        def findings
          @findings ||= report.fetch('rules').values.flat_map { |rule| rule.fetch('findings') }
        end

        def key
          "review:#{run_id}"
        end

        def marker
          "<!-- slop-guard:review:#{run_id} -->"
        end

        def path
          "#{client.repo_path}/pulls/#{number}/reviews"
        end

        # A status when this run's review was already delivered or definitively rejected; nil otherwise.
        def delivered_status
          matches = client.list(path).select { |review| owned?(review) && review['body'].to_s.include?(marker) }
          raise PublicationUncertain, 'Multiple matching bot reviews require operator inspection' if matches.size > 1

          if matches.first
            store.confirmed(key, matches.first.fetch('id'))
            return 'Inline review already delivered.'
          end
          intent = store.publication(key)
          return 'Inline locations were rejected; findings are included below.' if intent && intent['remote_id']&.zero?
          return nil unless intent

          raise PublicationUncertain, 'Previous inline review delivery could not be confirmed; no duplicate was sent'
        end

        # New comments to post, capped, and the count of existing threads updated in place.
        def comments_and_updates
          existing = client.list("#{client.repo_path}/pulls/#{number}/comments").select { |comment| owned?(comment) }
          updated = 0
          comments = findings.filter_map do |finding|
            anchor = finding.fetch('anchor')
            next unless changed.fetch(anchor['path'], []).include?(anchor['line'])

            body = body_for(finding, anchor)
            previous = thread_for(existing, finding, anchor)
            next { path: anchor['path'], line: anchor['line'], side: 'RIGHT', body: body } unless previous

            update(previous, body)
            updated += 1
            nil
          end
          [comments.uniq { |comment| comment[:body] }.first(MAX_INLINE), updated]
        end

        def thread_for(existing, finding, anchor)
          existing.find do |comment|
            comment['body'].to_s.include?(finding_marker(finding, anchor)) && comment['path'] == anchor['path'] &&
              comment['line'] == anchor['line'] && !comment['position'].nil?
          end
        end

        def update(previous, body)
          current.call
          client.patch("#{client.repo_path}/pulls/comments/#{previous.fetch('id')}", body: body)
        end

        def post(comments, updated)
          current.call
          body = "#{marker}\nSlop Guard advisory findings for `#{head}`. See the summary for coverage gaps."
          create(key) { client.post(path, commit_id: head, event: 'COMMENT', body: body, comments: comments) }
          "#{comments.size} new inline comment(s) posted; #{updated} existing comment(s) updated. " \
            'All findings are listed below.'
        rescue GitHubClient::Failure => e
          raise unless e.status == 422

          store.confirmed(key, 0)
          'GitHub rejected inline locations; all findings remain in the summary.'
        end

        # Stored runs from before finding ids existed fall back to the same digest inputs.
        def finding_marker(finding, anchor)
          id = finding['id'] ||
               SlopGuard.digest(finding.slice('rule', 'topic', 'scenario').merge('path' => anchor['path']))
          "<!-- slop-guard:finding:#{id} -->"
        end

        def body_for(finding, anchor)
          [finding_marker(finding, anchor),
           "**Slop Guard · #{Report.escape(Report.check_name(finding['rule']))}** (advisory)", '',
           "**Code:** #{Report.location(finding.fetch('anchor'), source_url: source_url)}", '',
           "**Context:** #{Report.escape(finding['scenario'] || finding['topic'])}", '',
           Report.escape(finding['message']), '', "**Suggested change:** #{Report.escape(finding['correction'])}", '',
           "Last reviewed commit: `#{head}`. Test execution is not established."].join("\n")
        end
      end
    end
  end
end
