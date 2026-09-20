# frozen_string_literal: true

require_relative 'candidates/extractor'

module SlopGuard
  # The supported Ruby methods, classes and tests found in a file tree, without executing reviewed code.
  class Candidates
    # dependencies: path => paths it reaches with require_relative, used to select evidence for the model.
    attr_reader :items, :gaps, :dependencies

    def self.extract(files, profile:)
      Extractor.new(files, profile: profile).call
    end

    def initialize(items:, gaps:, dependencies:)
      @items = items
      @gaps = gaps
      @dependencies = dependencies
    end

    def tests
      items.select { |item| item['kind'] == 'test' }
    end
  end
end
