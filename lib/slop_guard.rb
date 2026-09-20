# frozen_string_literal: true

require 'json'
require 'digest'
require 'pathname'
require 'yaml'
require 'time'
require 'fileutils'

# Shared review types and deterministic content fingerprints.
module SlopGuard
  ROOT = File.expand_path('..', __dir__)
  VERSION = '0.1.0'
  class Error < StandardError; end
  class InvalidInput < Error; end
  # The reviewed input is too large for this reviewer. A subclass of InvalidInput: the caller must shrink the
  # input, and retrying later will not help, unlike a budget or deadline LimitExceeded.
  class InputTooLarge < InvalidInput; end
  class ProviderError < Error; end
  class LimitExceeded < Error; end

  # Evidence bounds shared by every source adapter and by Snapshot. Prices and request bounds live on JevClient.
  module Limits
    FILE_BYTES = 16_384
    FILE_COUNT = 100
    BUNDLE_BYTES = 1_048_576
    BODY_BYTES = 16_384
    CHANGED_FILES = 50
    TEST_CANDIDATES = 100
    SCENARIOS = 12
  end

  def self.digest(value)
    Digest::SHA256.hexdigest(JSON.generate(value))
  end

  UNPRINTABLE = /[\u0000-\u001F\u007F-\u009F  ]/
  UNPRINTABLE_EXCEPT_NEWLINE = /[\u0000-\u0009\u000B-\u001F\u007F-\u009F  ]/

  # Untrusted text (repository paths, fixture names, provider bodies) reaches reports and the terminal. Control
  # characters, C1 controls and Unicode line separators are shown as escapes so they cannot forge report structure
  # or drive terminal escape sequences. Newlines are kept only where the caller prints multi-line text on purpose.
  def self.printable(text, keep_newlines: false)
    pattern = keep_newlines ? UNPRINTABLE_EXCEPT_NEWLINE : UNPRINTABLE
    text.to_s.gsub(pattern) { |char| char.inspect[1..-2] }
  end
end

# The review engine only. The evaluation harness is `slop_guard/eval`; the GitHub App is `slop_guard/service`.
%w[profile expectations candidates snapshot rules budget jev_client evaluator report git_source cli].each do |name|
  require_relative "slop_guard/#{name}"
end
