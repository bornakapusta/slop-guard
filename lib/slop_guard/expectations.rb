# frozen_string_literal: true

module SlopGuard
  class Expectations
    attr_reader :behaviors, :failures, :gaps

    def initialize(body)
      @behaviors = []
      @failures = []
      @gaps = []
      section = nil
      body.each_line do |line|
        if line.start_with?('## ')
          section = { 'Expected behavior' => behaviors, 'Failure cases' => failures }[line.delete_prefix('## ').strip]
        elsif section && line.match?(/^\s*- /)
          text = line.sub(/^\s*- /, '').strip
          explicit = text.match(/\A\[([a-z0-9_-]+)\]\s+(.+)\z/)
          section << { 'id' => explicit ? explicit[1] : SlopGuard.digest(text)[0, 12], 'text' => explicit ? explicit[2] : text }
        end
      end
      @gaps << 'Missing expected behavior' if behaviors.empty?
      @gaps << 'Too many scenarios' if behaviors.size + failures.size > 12
      ids = (behaviors + failures).map { |item| item['id'] }
      @gaps << 'Duplicate scenario IDs' unless ids.uniq.size == ids.size
    end
  end
end
