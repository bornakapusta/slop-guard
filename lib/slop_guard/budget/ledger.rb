# frozen_string_literal: true

module SlopGuard
  class Budget
    # The append-only session ledger shared by every reviewer process using one directory. One JSON line per
    # reservation; the total is re-read under an exclusive lock before each append.
    class Ledger
      def self.open(path)
        FileUtils.mkdir_p(File.dirname(path))
        new(path)
      end

      def initialize(path)
        @path = path
      end

      def reserve!(amount, limit:)
        File.open(@path, File::RDWR | File::CREAT, 0o600) do |file|
          file.flock(File::LOCK_EX)
          raise LimitExceeded, 'Evaluation session budget exhausted' if total(file) + amount > limit

          file.seek(0, IO::SEEK_END)
          file.puts(JSON.generate('at' => Time.now.utc.iso8601, 'reserved_usd' => amount))
          file.flush
          file.fsync
        end
      end

      private

      # Fails closed: an unreadable ledger means the session total is unknown, so no request may be reserved.
      def total(file)
        file.each_line.sum do |line|
          entry = JSON.parse(line)
          raise TypeError, 'ledger entry is not an object' unless entry.is_a?(Hash)

          amount = entry.fetch('reserved_usd', 0)
          raise TypeError, 'reservation is not numeric' unless amount.is_a?(Numeric)

          amount
        end
      rescue JSON::ParserError, TypeError
        raise InvalidInput, "Request ledger is corrupt: #{@path}"
      end
    end
  end
end
