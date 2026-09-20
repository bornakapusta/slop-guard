# frozen_string_literal: true

module SlopGuard
  # Persists conservative request reservations before contacting the provider. `open` prepares the ledger
  # directory and starts the review deadline; there is no other way to obtain a Budget.
  class Budget
    RESERVATION = 64_000 * 0.042 / 1_000_000
    attr_reader :attempts, :usage, :reserved

    def self.open(ledger:, **)
      FileUtils.mkdir_p(File.dirname(ledger))
      new(ledger: ledger, **)
    end
    private_class_method :new

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
    end

    def remaining
      @deadline - @clock.call
    end

    def reserve!
      raise LimitExceeded, 'Review deadline exceeded' unless remaining.positive?
      if attempts >= @max_attempts || reserved + RESERVATION > @review_limit
        raise LimitExceeded,
              'Review request budget exhausted'
      end

      File.open(@ledger, File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        total = ledger_total(file)
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

    private

    # Fails closed: an unreadable ledger means the session total is unknown, so no request may be reserved.
    def ledger_total(file)
      file.each_line.sum do |line|
        entry = JSON.parse(line)
        raise TypeError, 'ledger entry is not an object' unless entry.is_a?(Hash)

        amount = entry.fetch('reserved_usd', 0)
        raise TypeError, 'reservation is not numeric' unless amount.is_a?(Numeric)

        amount
      end
    rescue JSON::ParserError, TypeError
      raise InvalidInput, "Request ledger is corrupt: #{@ledger}"
    end
  end
end
