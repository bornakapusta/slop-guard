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
end

%w[dataset expectations candidates snapshot rules budget jev_client evaluator report eval_runner].each do |name|
  require_relative "slop_guard/#{name}"
end
