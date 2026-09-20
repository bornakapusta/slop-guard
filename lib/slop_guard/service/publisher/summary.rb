# frozen_string_literal: true

module SlopGuard
  module Service
    class Publisher
      # Delivers the one summary comment per pull request: updates the bot's existing summary or creates it.
      class Summary < Delivery
        MAX_BYTES = 60_000
        TRUNCATED_BYTES = 58_000

        def deliver(inline_status)
          matches = client.list(path).select do |comment|
            owned?(comment) && comment['body'].to_s.include?(SUMMARY_MARKER)
          end
          raise PublicationUncertain, 'Multiple bot summaries require operator inspection' if matches.size > 1

          comment = matches.first
          store.confirmed(key, comment.fetch('id')) if comment
          intent = store.publication(key)
          body = body_for(inline_status)
          current.call
          if comment
            client.patch("#{client.repo_path}/issues/comments/#{comment.fetch('id')}", body: body)
          elsif intent
            raise PublicationUncertain, 'Previous summary delivery could not be confirmed; no duplicate was sent'
          else
            create(key) { client.post(path, body: body) }
          end
        end

        private

        def key
          "summary:#{number}"
        end

        def path
          "#{client.repo_path}/issues/#{number}/comments"
        end

        def body_for(inline_status)
          body = "#{SUMMARY_MARKER}\n<!-- slop-guard:run:#{run_id} -->\n" \
                 "#{Report.markdown(report, source_url: source_url)}\n\n" \
                 "#{inline_status}\n\nReviewed commit: `#{head}`"
          body += previous_complete_section if report['status'] != 'complete'
          return body if body.bytesize <= MAX_BYTES

          "#{body.byteslice(0, TRUNCATED_BYTES).scrub}\n\n" \
            'Report display truncated. Full report is retained in the service database.'
        end

        # An incomplete review must not read as clearing the last complete one.
        def previous_complete_section
          previous = store.previous_complete(number, excluding: run_id)
          return '' unless previous

          label = 'Previous complete review — not cleared by this incomplete review'
          "\n\n<details><summary>#{label}</summary>\n\n#{Report.markdown(previous)}\n</details>"
        end
      end
    end
  end
end
