# frozen_string_literal: true

require_relative 'snapshot/trees'
require_relative 'snapshot/changes'
require_relative 'snapshot/evidence'

module SlopGuard
  # Bounded review evidence built from saved before and after file trees. `build` does the work; instances only
  # hold results and answer questions about them.
  class Snapshot
    attr_reader :profile, :body, :source, :gaps, :identity, :changed, :expectations, :candidates

    # Gap order is part of the report: omitted files, source gaps, oversized files, file count, changed-file count,
    # candidate gaps, then missing required files.
    def self.build(input, profile:)
      input_files = input.fetch('files')
      input_before = input.fetch('before')
      body = input.fetch('pr_body')
      source = input.fetch('source', {})
      gaps = input.fetch('omitted', []).map { |path| "Omitted file: #{path}" }
      gaps.concat(input.fetch('source_gaps', []))
      raise InvalidInput, 'PR body exceeds 16 KiB' if body.bytesize > Limits::BODY_BYTES

      # The identity covers the raw input, before any file is filtered or dropped.
      identity = SlopGuard.digest([input, profile.to_h])
      trees = Trees.select(input_files, input_before, input.fetch('skipped_paths', []), profile: profile, gaps: gaps)
      changed = Changes.diff(trees.before, trees.files)
      gaps << "More than #{Limits::CHANGED_FILES} changed files" if changed.size > Limits::CHANGED_FILES
      candidates = Candidates.extract(trees.files, profile: profile)
      gaps.concat(candidates.gaps)
      profile.required_files.each { |path| gaps << "#{path} is missing" unless trees.files.key?(path) }
      new(profile: profile, trees: trees, body: body, source: source, gaps: gaps, identity: identity,
          changed: changed, expectations: Expectations.parse(body), candidates: candidates)
    end

    def initialize(profile:, trees:, body:, source:, gaps:, identity:, changed:, expectations:, candidates:)
      @profile = profile
      @trees = trees
      @body = body
      @source = source
      @gaps = gaps
      @identity = identity
      @changed = changed
      @expectations = expectations
      @candidates = candidates
    end

    def files
      trees.files
    end

    def before
      trees.before
    end

    def skipped
      trees.skipped
    end

    def changed_candidates(kind)
      candidates.items.select do |candidate|
        candidate['kind'] == kind && !profile.test_path?(candidate['path']) &&
          changed.fetch(candidate['path'], []).any? { |line| line.between?(candidate['line'], candidate['end_line']) }
      end
    end

    def selected_paths
      evidence.paths
    end

    def state
      evidence.state
    end

    def state_bytes
      JSON.generate(state).bytesize
    end

    # For a design candidate: its first changed line. For a test scenario: the changed method whose name the
    # scenario text mentions, else the first changed line of any production Ruby file.
    def anchor(candidate = nil, scenario: nil)
      candidate ||= scenario && changed_candidates('method').find do |method|
        short = method['name'].split('#').last.to_s
        !short.empty? && scenario.match?(/\b#{Regexp.escape(short)}\b/)
      end
      if candidate
        line = changed.fetch(candidate['path'], []).grep(candidate['line']..candidate['end_line']).first
        return { 'path' => candidate['path'], 'line' => line } if line
      end
      path, lines = changed.find { |file, value| profile.anchorable?(file) && !value.empty? }
      path ? { 'path' => path, 'line' => lines.first } : nil
    end

    private

    attr_reader :trees

    def evidence
      @evidence ||= Evidence.new(self)
    end
  end
end
