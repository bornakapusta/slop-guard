# frozen_string_literal: true

module SlopGuard
  class Budget
    RESERVATION = 64_000 * 0.042 / 1_000_000
    attr_reader :attempts, :usage, :reserved

    def initialize(ledger:, session_limit: 2.0, review_limit: 0.10, max_attempts: 20, seconds: 120,
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @ledger = ledger
      @session_limit = session_limit
      @review_limit = review_limit
      @max_attempts = max_attempts
      @clock = clock
      @deadline = clock.call + seconds
      @attempts = 0
      @usage = 0
      @reserved = 0.0
      FileUtils.mkdir_p(File.dirname(ledger))
    end

    def remaining
      @deadline - @clock.call
    end

    def reserve!
      raise LimitExceeded, 'Review deadline exceeded' unless remaining.positive?
      raise LimitExceeded, 'Review request budget exhausted' if attempts >= @max_attempts || reserved + RESERVATION > @review_limit
      File.open(@ledger, File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        total = file.each_line.sum { |line| JSON.parse(line).fetch('reserved_usd', 0) }
        raise LimitExceeded, 'Evaluation session budget exhausted' if total + RESERVATION > @session_limit
        file.seek(0, IO::SEEK_END)
        file.puts(JSON.generate('at' => Time.now.utc.iso8601, 'reserved_usd' => RESERVATION))
        file.flush
        file.fsync
      end
      @attempts += 1
      @reserved += RESERVATION
    end

    def record_usage(tokens)
      @usage += tokens
    end
  end
end
