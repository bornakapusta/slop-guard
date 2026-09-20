# frozen_string_literal: true

module SlopGuard
  # A saved before/files JSON document given to `bin/review --input`. Bounded before parsing; the caller adds the
  # expectations text.
  module InputDocument
    MAX_BYTES = Limits::BUNDLE_BYTES * 2

    def self.read(path)
      raw = File.binread(path, MAX_BYTES + 1)
      raise InputTooLarge, 'Input document exceeds 2 MiB' if raw.bytesize > MAX_BYTES

      input = JSON.parse(raw)
      raise InvalidInput, 'Input document must be an object' unless input.is_a?(Hash)

      input
    rescue JSON::ParserError
      raise InvalidInput, 'Input document is not valid JSON'
    end
  end
end
