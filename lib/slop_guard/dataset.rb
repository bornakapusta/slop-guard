# frozen_string_literal: true

module SlopGuard
  # Saved patches are data: replacement blobs with preimage digests, never shell commands.
  class Dataset
    attr_reader :root, :manifest

    def initialize(root)
      @root = Pathname.new(root).realpath
      @manifest = read_json('manifest.json')
    end

    def cases(split = nil)
      manifest.fetch('cases').select { |entry| split.nil? || entry.fetch('split') == split }
    end

    def read_json(relative)
      path = safe_path(relative)
      raise InvalidInput, 'Fixture file exceeds 1 MiB' if path.size > 1_048_576
      JSON.parse(path.read)
    rescue JSON::ParserError, Errno::ENOENT, KeyError
      raise InvalidInput, "Invalid or missing fixture: #{relative}"
    end

    def safe_path(relative)
      parts = relative.to_s.split('/')
      if parts.empty? || Pathname.new(relative).absolute? || parts.any? { |part| ['', '.', '..'].include?(part) }
        raise InvalidInput, 'Unsafe fixture path'
      end
      path = root
      parts.each do |part|
        path = path.join(part)
        raise InvalidInput, 'Symlinks are not allowed in fixtures' if path.symlink?
      end
      path
    end

    def input(id)
      entry = cases.find { |item| item.fetch('id') == id }
      raise InvalidInput, 'Unknown case ID' unless entry
      record = read_json(entry.fetch('input'))
      before = read_json(record.fetch('baseline')).fetch('files')
      after = before.dup
      record.fetch('changes').each do |path, change|
        validate_source_path!(path)
        raise InvalidInput, "Patch preimage mismatch: #{path}" unless SlopGuard.digest(before[path]) == change.fetch('before_sha256')
        change.fetch('after').nil? ? after.delete(path) : after[path] = change['after']
      end
      omitted = record.fetch('omitted', [])
      omitted.each { |path| validate_source_path!(path); after.delete(path) }
      # Labels, case ID, split and rationale are deliberately absent from the review input.
      { 'before' => before, 'files' => after, 'pr_body' => record.fetch('pr_body'), 'omitted' => omitted }
    rescue KeyError, TypeError
      raise InvalidInput, 'Invalid saved patch shape'
    end

    def labels(id)
      entry = cases.find { |item| item.fetch('id') == id }
      read_json(entry.fetch('labels'))
    end

    def validate!
      raise InvalidInput, 'Dataset must contain 16 development and 8 holdout cases' unless cases('development').size == 16 && cases('holdout').size == 8
      raise InvalidInput, 'Duplicate case IDs' unless cases.map { |entry| entry.fetch('id') }.uniq.size == cases.size
      families = cases.group_by { |entry| entry.fetch('family') }
      raise InvalidInput, 'Case family crosses dataset splits' if families.values.any? { |entries| entries.map { |entry| entry['split'] }.uniq.size > 1 }
      cases.each do |entry|
        raise InvalidInput, 'Unknown split' unless %w[development holdout].include?(entry['split'])
        data = input(entry.fetch('id'))
        label = labels(entry.fetch('id'))
        raise InvalidInput, 'Every rule needs a label' unless label.fetch('outcomes').keys.sort == %w[G1 G2 G3 G4]
        raise InvalidInput, 'Unknown expected outcome' unless label['outcomes'].values.all? { |value| %w[concern no_concern not_applicable inconclusive].include?(value) }
        raise InvalidInput, 'Label rationale required' if label.fetch('rationale').strip.empty?
        label.fetch('findings').each do |finding|
          raise InvalidInput, 'Finding rule must have concern outcome' unless label['outcomes'][finding.fetch('rule')] == 'concern'
          finding.fetch('anchors').each do |anchor|
            body = data.fetch('files')[anchor.fetch('path')]
            line = anchor.fetch('line')
            raise InvalidInput, 'Invalid expected anchor' unless body && line.is_a?(Integer) && line.between?(1, body.lines.size)
          end
        end
      end
      true
    rescue KeyError, NoMethodError
      raise InvalidInput, 'Invalid dataset manifest or labels'
    end

    private

    def validate_source_path!(path)
      raise InvalidInput, 'Unsafe source path' unless path.is_a?(String) && !path.start_with?('/') && path.split('/').none? { |part| ['', '.', '..'].include?(part) }
    end
  end
end
