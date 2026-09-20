# frozen_string_literal: true

module SlopGuard
  # Renders escaped advisory findings without implying overall correctness.
  module Report
    def self.markdown(result)
      lines = ["# Slop Guard: #{result.fetch('status')}", '', "Snapshot: `#{result.fetch('snapshot')}`",
               'Advisory review of inspected evidence. Test execution and overall correctness are not established.', '']
      shared_test_concerns = {}
      result.fetch('rules').each do |id, rule|
        lines << "## #{id}: #{rule.fetch('outcome')}"
        rule.fetch('findings').each do |finding|
          anchor = finding.fetch('anchor')
          if %w[G1 G2].include?(id) && finding['scenario']
            key = [finding['scenario'], anchor]
            if shared_test_concerns[key]
              lines << "- Shared test concern: see #{shared_test_concerns[key]}; also applies to #{id}."
              next
            end
            shared_test_concerns[key] = id
          end
          lines << "- #{escape(finding['message'])} — #{escape(anchor['path'])}:#{anchor['line']} " \
                   "(#{escape(finding['scenario'] || finding['topic'])}). #{escape(finding['correction'])}"
          lines << "  Review signals: #{escape(JSON.generate(finding['readings']))}; " \
                   "thresholds: #{escape(JSON.generate(finding['thresholds']))}. These are not certainty scores."
        end
        rule.fetch('gaps').each { |gap| lines << "- Incomplete: #{escape(gap)}" }
        lines << ''
      end
      lines.join("\n")
    end

    def self.escape(text)
      text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('@', '@‌').gsub(/[\[\]`*_\\]/) do |char|
        "\\#{char}"
      end
    end
  end
end
