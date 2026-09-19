# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require_relative '../lib/slop_guard'
RSpec.configure do |config|
  config.order = :random
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
end
