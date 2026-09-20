# frozen_string_literal: true

module SlopGuard
  # Renders escaped advisory findings without implying overall correctness.
  module Report
    # U+200C ZERO WIDTH NON-JOINER: inserted after "@" so GitHub does not resolve @mentions from untrusted evidence.
    MENTION_BREAK = [0x200C].pack('U').freeze

    CHECK_NAMES = { 'G1' => 'Behavior test coverage', 'G2' => 'Failure case coverage',
                    'G3' => 'Focused responsibilities', 'G4' => 'Unnecessary abstractions' }.freeze
    OUTCOMES = { 'concern' => 'Needs attention', 'no_concern' => 'No concern found',
                 'inconclusive' => 'Could not determine', 'not_applicable' => 'Not applicable' }.freeze

    def self.check_name(id)
      CHECK_NAMES.fetch(id, id)
    end

    def self.markdown(result, source_url: nil)
      rules = result.fetch('rules')
      count = rules.values.sum { |rule| rule.fetch('findings').size }
      lines = ['## Slop Guard review', '', overview(result.fetch('status'), count), '', *check_table(rules)]
      rules.each do |id, rule|
        rule.fetch('findings').each { |finding| lines.concat(finding_lines(id, finding, source_url)) }
      end
      unresolved = rules.reject { |_id, rule| rule.fetch('gaps').empty? }
      unless unresolved.empty?
        lines.push('', '### What still needs review', '')
        unresolved.each do |id, rule|
          rule.fetch('gaps').each { |gap| lines << "- **#{escape(check_name(id))}:** #{escape(explain_gap(gap))}" }
        end
      end
      lines.push('', 'Slop Guard inspected code and tests; it did not run them. This is an advisory review.', '')
      lines.concat(diagnostics(result)).join("\n")
    end

    def self.check_table(rules)
      rows = rules.map do |id, rule|
        outcome = OUTCOMES.fetch(rule.fetch('outcome'), rule['outcome'])
        outcome += '; some checks unresolved' if rule['outcome'] == 'concern' && !rule.fetch('gaps').empty?
        "| #{escape(check_name(id))} | #{escape(outcome)} |"
      end
      ['| Check | Result |', '| --- | --- |', *rows]
    end

    def self.diagnostics(result)
      lines = ['<details><summary>Review diagnostics</summary>', '',
               "Snapshot: `#{escape(result.fetch('snapshot'))}`", '']
      rules = result.fetch('rules')
      rules.each do |id, rule|
        lines << "- #{escape(id)}: #{escape(rule.fetch('outcome'))}"
        rule.fetch('gaps').each { |gap| lines << "  - #{escape(gap)}" }
        rule.fetch('findings').each do |finding|
          lines << "  - Review signals: #{escape(JSON.generate(finding['readings']))}; " \
                   "thresholds: #{escape(JSON.generate(finding['thresholds']))}. These are not certainty scores."
        end
      end
      lines.push('', '</details>')
    end

    def self.overview(status, count)
      findings = if count.zero?
                   'No actionable findings were reported.'
                 else
                   "#{count} finding#{'s' unless count == 1} to review."
                 end
      case status
      when 'failed'
        "#{findings} **Review stopped before completion.** See the unresolved checks below."
      when 'incomplete'
        "#{findings} **Some checks could not reach a conclusion.** This is not an all-clear."
      else
        "#{findings} All configured checks finished."
      end
    end

    def self.finding_lines(id, finding, source_url)
      ['', "### #{escape(check_name(id))}", '',
       "**Code:** #{location(finding.fetch('anchor'), source_url: source_url)}", '',
       "**Context:** #{escape(finding['scenario'] || finding['topic'])}", '',
       escape(finding['message']), '', "**Suggested change:** #{escape(finding['correction'])}"]
    end

    def self.location(anchor, source_url: nil)
      label = escape("#{anchor.fetch('path')}:#{anchor.fetch('line')}")
      return label unless source_url

      # Encode each path segment so filenames cannot escape the Markdown link destination.
      path = anchor.fetch('path').split('/').map do |segment|
        segment.bytes.map { |byte| byte.chr.match?(/[a-zA-Z0-9_~-]/) ? byte.chr : format('%%%02X', byte) }.join
      end.join('/')
      "[#{label}](#{source_url}/#{path}#L#{Integer(anchor.fetch('line'))})"
    end

    def self.explain_gap(gap)
      case gap
      when /\AUnclear applicability or expectation: (.+)\z/
        "Could not establish whether requirement '#{Regexp.last_match(1)}' is clear and relevant to this change. " \
        'Check the expected behavior in the PR description.'
      when /\AConflicting or uncertain coverage evidence: (.+)\z/
        "Could not establish whether tests prove requirement '#{Regexp.last_match(1)}'. " \
        'Check its assertions manually; this does not establish that a test is missing.'
      when /\AConflicting or uncertain design evidence: (.+)\z/
        "Could not reach a supported design judgment for '#{Regexp.last_match(1)}'. Manual review is needed."
      else
        gap
      end
    end

    def self.escape(text)
      escaped = text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('@', "@#{MENTION_BREAK}")
      escaped = escaped.gsub(/[\[\]`*_\\|]/) { |char| "\\#{char}" }
      # Last, so the visible escapes it produces are not themselves re-escaped.
      SlopGuard.printable(escaped)
    end
  end
end
