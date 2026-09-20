# frozen_string_literal: true

module SlopGuard
  # Renders escaped advisory findings without implying overall correctness.
  module Report
    # U+200C ZERO WIDTH NON-JOINER: inserted after "@" so GitHub does not resolve @mentions from untrusted evidence.
    MENTION_BREAK = [0x200C].pack('U').freeze

    def self.markdown(result)
      lines = ["# Slop Guard: #{result.fetch('status')}", '', "Snapshot: `#{result.fetch('snapshot')}`",
               'Advisory review of inspected evidence. Test execution and overall correctness are not established.', '']
      result.fetch('rules').each do |id, rule|
        lines << "## #{id}: #{rule.fetch('outcome')}"
        rule.fetch('findings').each do |finding|
          anchor = finding.fetch('anchor')
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
      escaped = text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('@', "@#{MENTION_BREAK}")
      escaped = escaped.gsub(/[\[\]`*_\\]/) { |char| "\\#{char}" }
      # Last, so the visible escapes it produces are not themselves re-escaped.
      SlopGuard.printable(escaped)
    end
  end
end
