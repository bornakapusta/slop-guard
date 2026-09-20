# frozen_string_literal: true

require_relative 'publisher/delivery'
require_relative 'publisher/inline_review'
require_relative 'publisher/summary'

module SlopGuard
  module Service
    # Publishes changed-line comments and one summary per pull request, reconciling uncertain creates. Holds only
    # the shared collaborators; every `publish` runs in fresh per-delivery objects.
    class Publisher
      SUMMARY_MARKER = '<!-- slop-guard:summary:v1 -->'
      MAX_INLINE = 20

      def initialize(client:, store:)
        @client = client
        @store = store
      end

      def publish(number:, head:, run_id:, report:, changed:, current:)
        delivery = { client: client, store: store, number: number, head: head, run_id: run_id, report: report,
                     changed: changed, current: current }
        inline_status = InlineReview.new(**delivery).deliver
        Summary.new(**delivery).deliver(inline_status)
        current.call
      end

      private

      attr_reader :client, :store
    end
  end
end
