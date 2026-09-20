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
  class ProviderError < Error; end
  class LimitExceeded < Error; end

  def self.digest(value)
    Digest::SHA256.hexdigest(JSON.generate(value))
  end

  UNPRINTABLE = /[\u0000-\u001F\u007F-\u009F\u2028\u2029]/
  UNPRINTABLE_EXCEPT_NEWLINE = /[\u0000-\u0009\u000B-\u001F\u007F-\u009F\u2028\u2029]/

  # Untrusted text (repository paths, fixture names, provider bodies) reaches reports and the terminal. Control
  # characters, C1 controls and Unicode line separators are shown as escapes so they cannot forge report structure
  # or drive terminal escape sequences. Newlines are kept only where the caller prints multi-line text on purpose.
  def self.printable(text, keep_newlines: false)
    pattern = keep_newlines ? UNPRINTABLE_EXCEPT_NEWLINE : UNPRINTABLE
    text.to_s.gsub(pattern) { |char| char.inspect[1..-2] }
  end
end

%w[dataset git_source expectations candidates snapshot rules budget jev_client evaluator report eval_runner
   evaluation_analysis].each do |name|
  require_relative "slop_guard/#{name}"
end
