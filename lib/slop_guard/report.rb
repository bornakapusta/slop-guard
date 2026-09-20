# frozen_string_literal: true

module SlopGuard
  # Renders a review report as advisory Markdown without implying overall correctness.
  module Report
    OUTCOMES = { 'concern' => 'Needs attention', 'no_concern' => 'No concern found',
                 'inconclusive' => 'Could not determine', 'not_applicable' => 'Not applicable' }.freeze

    def self.markdown(result, source_url: nil)
      rules = result.fetch('rules')
      count = rules.values.sum { |rule| rule.fetch('findings').size }
      lines = ['## Slop Guard review', '', overview(result.fetch('status'), count), '', *check_table(rules)]
      rules.each do |id, rule|
        rule.fetch('findings').each { |finding| lines.concat(finding_lines(id, finding, source_url)) }
      end
      lines.concat(unresolved_lines(rules))
      lines.push('', 'Slop Guard inspected code and tests; it did not run them. This is an advisory review.', '')
      lines.concat(diagnostics(result)).join("\n")
    end

    def self.check_table(rules)
      rows = rules.map do |id, rule|
        outcome = OUTCOMES.fetch(rule.fetch('outcome'), rule['outcome'])
        outcome += '; some checks unresolved' if rule['outcome'] == 'concern' && !rule.fetch('gaps').empty?
        "| #{Markdown.escape(Markdown.check_name(id))} | #{Markdown.escape(outcome)} |"
      end
      ['| Check | Result |', '| --- | --- |', *rows]
    end

    def self.unresolved_lines(rules)
      unresolved = rules.reject { |_id, rule| rule.fetch('gaps').empty? }
      return [] if unresolved.empty?

      lines = ['', '### What still needs review', '']
      unresolved.each do |id, rule|
        rule.fetch('gaps').each do |gap|
          lines << "- **#{Markdown.escape(Markdown.check_name(id))}:** #{Markdown.escape(explain_gap(gap))}"
        end
      end
      lines
    end

    def self.diagnostics(result)
      lines = ['<details><summary>Review diagnostics</summary>', '',
               "Snapshot: `#{Markdown.escape(result.fetch('snapshot'))}`", '']
      result.fetch('rules').each do |id, rule|
        lines << "- #{Markdown.escape(id)}: #{Markdown.escape(rule.fetch('outcome'))}"
        rule.fetch('gaps').each { |gap| lines << "  - #{Markdown.escape(gap)}" }
        rule.fetch('findings').each do |finding|
          lines << "  - Review signals: #{Markdown.escape(JSON.generate(finding['readings']))}; " \
                   "thresholds: #{Markdown.escape(JSON.generate(finding['thresholds']))}. " \
                   'These are not certainty scores.'
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
      ['', "### #{Markdown.escape(Markdown.check_name(id))}", '',
       "**Code:** #{Markdown.location(finding.fetch('anchor'), source_url: source_url)}", '',
       "**Context:** #{Markdown.escape(finding['scenario'] || finding['topic'])}", '',
       Markdown.escape(finding['message']), '', "**Suggested change:** #{Markdown.escape(finding['correction'])}"]
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
  end
end
