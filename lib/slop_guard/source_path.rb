# frozen_string_literal: true

module SlopGuard
  # Repository-relative path safety, shared by every source of file trees. Each caller chooses its own error
  # message and whether control characters are rejected; the rule itself lives in one place.
  module SourcePath
    UNSAFE_SEGMENTS = ['', '.', '..'].freeze
    CONTROL = /[[:cntrl:]]/

    def self.unsafe?(path, control_chars: false)
      return true unless path.is_a?(String) && path.valid_encoding?
      return true if path.start_with?('/') || (control_chars && path.match?(CONTROL))

      path.split('/').intersect?(UNSAFE_SEGMENTS)
    end
  end
end
