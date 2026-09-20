# frozen_string_literal: true

if ENV['COVERAGE'] == '1'
  require 'simplecov'
  SimpleCov.start do
    cover 'lib/**/*.rb', 'script/**/*.rb', 'bin/*'
    enable_coverage :branch
    formats :html, :json
    merging false
  end
end

require 'tmpdir'
require 'fileutils'
require_relative '../lib/slop_guard'
Dir[File.join(__dir__, 'support/**/*.rb')].each { |file| require file }
RSpec.configure do |config|
  config.order = :random
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
end
