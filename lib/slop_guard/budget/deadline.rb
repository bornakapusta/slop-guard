# frozen_string_literal: true

module SlopGuard
  class Budget
    # A monotonic wall-clock limit that starts when it is created.
    class Deadline
      def initialize(seconds:, clock:)
        @clock = clock
        @at = clock.call + seconds
      end

      def remaining
        @at - @clock.call
      end

      def expired?
        !remaining.positive?
      end
    end
  end
end
