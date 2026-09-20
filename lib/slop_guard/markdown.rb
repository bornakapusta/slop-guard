# frozen_string_literal: true

module SlopGuard
  # Markdown fragments built from untrusted text: escaping, source links and check names. Shared by the review
  # report, the GitHub publisher and the evaluation summary.
  module Markdown
    # U+200C ZERO WIDTH NON-JOINER: inserted after "@" so GitHub does not resolve @mentions from untrusted evidence.
    MENTION_BREAK = [0x200C].pack('U').freeze

    CHECK_NAMES = { 'G1' => 'Behavior test coverage', 'G2' => 'Failure case coverage',
                    'G3' => 'Focused responsibilities', 'G4' => 'Unnecessary abstractions' }.freeze

    def self.check_name(id)
      CHECK_NAMES.fetch(id, id)
    end

    def self.escape(text)
      escaped = text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('@', "@#{MENTION_BREAK}")
      escaped = escaped.gsub(/[\[\]`*_\\|]/) { |char| "\\#{char}" }
      # Last, so the visible escapes it produces are not themselves re-escaped.
      SlopGuard.printable(escaped)
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
  end
end
