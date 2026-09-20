# frozen_string_literal: true

module SlopGuard
  # What counts as reviewable source text: a valid UTF-8 String with no NUL byte.
  module SourceText
    def self.valid?(text)
      text.is_a?(String) && text.valid_encoding? && !text.include?("\0")
    end
  end
end
