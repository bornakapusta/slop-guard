# frozen_string_literal: true

require_relative 'budget/deadline'
require_relative 'budget/ledger'

module SlopGuard
  # The per-review request guard: a deadline, an attempt cap, a per-review cost cap, and the shared session
  # ledger. `open` prepares the ledger and starts the deadline; there is no other way to obtain a Budget.
  class Budget
    RESERVATION = 64_000 * 0.042 / 1_000_000
    attr_reader :attempts, :usage, :reserved

    def self.open(ledger:, **)
      new(ledger: Ledger.open(ledger), **)
    end
    private_class_method :new

    def initialize(ledger:, session_limit: 2.0, review_limit: 0.10, max_attempts: 20, seconds: 120,
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @ledger = ledger
      @session_limit = session_limit
      @review_limit = review_limit
      @max_attempts = max_attempts
      @deadline = Deadline.new(seconds: seconds, clock: clock)
      @attempts = 0
      @usage = 0
      @reserved = 0.0
    end

    def remaining
      deadline.remaining
    end

    def reserve!
      raise LimitExceeded, 'Review deadline exceeded' if deadline.expired?
      raise LimitExceeded, 'Review request budget exhausted' if attempts >= max_attempts || over_review_limit?

      ledger.reserve!(RESERVATION, limit: session_limit)
      @attempts += 1
      @reserved += RESERVATION
    end

    def record_usage(tokens)
      @usage += tokens
    end

    private

    attr_reader :ledger, :session_limit, :review_limit, :max_attempts, :deadline

    def over_review_limit?
      reserved + RESERVATION > review_limit
    end
  end
end
