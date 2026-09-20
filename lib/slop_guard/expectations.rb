# frozen_string_literal: true

module SlopGuard
  # The explicit behavior and failure scenarios of a PR description.
  class Expectations
    SECTIONS = { 'Expected behavior' => :behaviors, 'Failure cases' => :failures }.freeze
    BULLET = /^\s*- /
    NAMED = /\A\[([a-z0-9_-]+)\]\s+(.+)\z/

    attr_reader :behaviors, :failures, :gaps

    def self.parse(body)
      sections = { behaviors: [], failures: [] }
      current = nil
      body.each_line do |line|
        if line.start_with?('## ')
          current = sections[SECTIONS[line.delete_prefix('## ').strip]]
        elsif current && line.match?(BULLET)
          current << scenario(line.sub(BULLET, '').strip)
        end
      end
      new(**sections, gaps: gaps_for(sections[:behaviors], sections[:failures]))
    end

    def self.scenario(text)
      explicit = text.match(NAMED)
      { 'id' => explicit ? explicit[1] : SlopGuard.digest(text)[0, 12], 'text' => explicit ? explicit[2] : text }
    end

    def self.gaps_for(behaviors, failures)
      gaps = []
      gaps << 'Missing expected behavior' if behaviors.empty?
      gaps << 'Too many scenarios' if behaviors.size + failures.size > Limits::SCENARIOS
      ids = (behaviors + failures).map { |item| item['id'] }
      gaps << 'Duplicate scenario IDs' unless ids.uniq.size == ids.size
      gaps
    end
    private_class_method :scenario, :gaps_for

    def initialize(behaviors:, failures:, gaps:)
      @behaviors = behaviors
      @failures = failures
      @gaps = gaps
    end
  end
end
