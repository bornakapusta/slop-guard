# frozen_string_literal: true

module SlopGuard
  module Service
    # Publishes changed-line comments and one summary, reconciling uncertain creates.
    class Publisher
      SUMMARY_MARKER = '<!-- slop-guard:summary:v1 -->'
      MAX_INLINE = 20

      def initialize(client:, store:)
        @client = client
        @store = store
      end

      def publish(number:, head:, run_id:, report:, changed:, current:)
        @current = current
        @pr = number
        @head = head
        @run_id = run_id
        findings = report.fetch('rules').values.flat_map { |rule| rule.fetch('findings') }
        inline_status = inline(findings, changed)
        summary(report, inline_status)
        @current.call
      end

      private

      def owned?(comment)
        comment.dig('user', 'type') == 'Bot' && comment.dig('user', 'login') == @client.bot_login
      end

      def inline(findings, changed)
        marker = "<!-- slop-guard:review:#{@run_id} -->"
        path = "#{@client.repo_path}/pulls/#{@pr}/reviews"
        matches = @client.list(path).select { |review| owned?(review) && review['body'].to_s.include?(marker) }
        raise PublicationUncertain, 'Multiple matching bot reviews require operator inspection' if matches.size > 1

        key = "review:#{@run_id}"
        if matches.first
          @store.confirmed(key, matches.first.fetch('id'))
          return 'Inline review already delivered.'
        end
        intent = @store.publication(key)
        return 'Inline locations were rejected; findings are included below.' if intent && intent['remote_id']&.zero?
        if intent
          raise PublicationUncertain, 'Previous inline review delivery could not be confirmed; no duplicate was sent'
        end

        existing = @client.list("#{@client.repo_path}/pulls/#{@pr}/comments").select { |comment| owned?(comment) }
        comments = findings.filter_map do |finding|
          anchor = finding.fetch('anchor')
          next unless changed.fetch(anchor['path'], []).include?(anchor['line'])

          id = finding['id'] ||
               SlopGuard.digest(finding.slice('rule', 'topic', 'scenario').merge('path' => anchor['path']))
          finding_marker = "<!-- slop-guard:finding:#{id} -->"
          body = inline_body(finding, finding_marker)
          previous = existing.find do |comment|
            comment['body'].to_s.include?(finding_marker) && comment['path'] == anchor['path'] &&
              comment['line'] == anchor['line'] && !comment['position'].nil?
          end
          if previous
            @current.call
            @client.patch("#{@client.repo_path}/pulls/comments/#{previous.fetch('id')}", body: body)
            next
          end
          { path: anchor['path'], line: anchor['line'], side: 'RIGHT', body: body }
        end
        comments = comments.uniq { |comment| comment[:body] }.first(MAX_INLINE)
        return 'Findings are in the summary or existing inline threads.' if comments.empty?

        @current.call
        @store.intend(key)
        begin
          body = "#{marker}\nSlop Guard advisory findings for `#{@head}`. See the summary for coverage gaps."
          review = @client.post(path, commit_id: @head, event: 'COMMENT', body: body, comments: comments)
          @store.confirmed(key, review.fetch('id'))
        rescue GitHubClient::Failure => e
          if e.status == 422
            @store.confirmed(key, 0)
            return 'GitHub rejected inline locations; all findings remain in the summary.'
          end
          @store.clear_intent(key) if definitive_rejection?(e)
          raise
        end
        "Up to #{MAX_INLINE} inline findings delivered; all findings are listed below."
      end

      def inline_body(finding, marker)
        [marker, "**Slop Guard · #{Report.escape(finding['rule'])}** (advisory)", '',
         Report.escape(finding['message']), '', Report.escape(finding['correction']), '',
         "Context: #{Report.escape(finding['scenario'] || finding['topic'])}", '',
         "Last reviewed commit: `#{@head}`. Test execution is not established."].join("\n")
      end

      def summary(report, inline_status)
        path = "#{@client.repo_path}/issues/#{@pr}/comments"
        matches = @client.list(path).select do |comment|
          owned?(comment) && comment['body'].to_s.include?(SUMMARY_MARKER)
        end
        raise PublicationUncertain, 'Multiple bot summaries require operator inspection' if matches.size > 1

        key = "summary:#{@pr}"
        comment = matches.first
        @store.confirmed(key, comment.fetch('id')) if comment
        intent = @store.publication(key)
        body = summary_body(report, inline_status)
        @current.call
        if comment
          @client.patch("#{@client.repo_path}/issues/comments/#{comment.fetch('id')}", body: body)
        elsif intent
          raise PublicationUncertain, 'Previous summary delivery could not be confirmed; no duplicate was sent'
        else
          @store.intend(key)
          begin
            created = @client.post(path, body: body)
            @store.confirmed(key, created.fetch('id'))
          rescue GitHubClient::Failure => e
            @store.clear_intent(key) if definitive_rejection?(e)
            raise
          end
        end
      end

      def summary_body(report, inline_status)
        body = "#{SUMMARY_MARKER}\n<!-- slop-guard:run:#{@run_id} -->\n" \
               "Reviewed commit: `#{@head}`\n\n#{inline_status}\n\n#{Report.markdown(report)}"
        if report['status'] != 'complete'
          previous = @store.previous_complete(@pr, excluding: @run_id)
          if previous
            label = 'Previous complete review — not cleared by this incomplete review'
            body += "\n\n<details><summary>#{label}</summary>\n\n#{Report.markdown(previous)}\n</details>"
          end
        end
        return body if body.bytesize <= 60_000

        "#{body.byteslice(0,
                          58_000).scrub}\n\nReport display truncated. Full report is retained in the service database."
      end

      def definitive_rejection?(error)
        [400, 401, 403, 404, 422, 429].include?(error.status)
      end
    end
  end
end
