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
      if parts.empty? || Pathname.new(relative).absolute? || parts.intersect?(['', '.', '..'])
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
      record = read_json(entry_for(id).fetch('input'))
      before = read_json(record.fetch('baseline')).fetch('files')
      after = before.dup
      record.fetch('changes').each do |path, change|
        validate_source_path!(path)
        unless SlopGuard.digest(before[path]) == change.fetch('before_sha256')
          raise InvalidInput,
                "Patch preimage mismatch: #{path}"
        end

        if change.fetch('after').nil?
          after.delete(path)
        else
          after[path] = change['after']
        end
      end
      omitted = record.fetch('omitted', [])
      omitted.each do |path|
        validate_source_path!(path)
        after.delete(path)
      end
      # Labels, case ID, split and rationale are deliberately absent from the review input.
      { 'before' => before, 'files' => after, 'pr_body' => record.fetch('pr_body'), 'omitted' => omitted }
    rescue KeyError, TypeError
      raise InvalidInput, 'Invalid saved patch shape'
    end

    def labels(id)
      read_json(entry_for(id).fetch('labels'))
    end

    def validate!
      validate_manifest!
      cases.each do |entry|
        data = input(entry.fetch('id'))
        validate_labels!(labels(entry.fetch('id')), data.fetch('files'))
      end
      true
    rescue KeyError, TypeError
      raise InvalidInput, 'Invalid dataset manifest or labels'
    end

    private

    # The fixed demo split contract: 16 development and 8 held-out cases, families never crossing splits.
    def validate_manifest!
      unless cases('development').size == 16 && cases('holdout').size == 8
        raise InvalidInput, 'Dataset must contain 16 development and 8 holdout cases'
      end
      raise InvalidInput, 'Duplicate case IDs' unless cases.map { |entry| entry.fetch('id') }.uniq.size == cases.size

      families = cases.group_by { |entry| entry.fetch('family') }
      if families.values.any? { |entries| entries.map { |entry| entry['split'] }.uniq.size > 1 }
        raise InvalidInput, 'Case family crosses dataset splits'
      end

      cases.each do |entry|
        raise InvalidInput, 'Unknown split' unless %w[development holdout].include?(entry['split'])
      end
    end

    def validate_labels!(label, files)
      unless label.is_a?(Hash) && label['outcomes'].is_a?(Hash) && label['findings'].is_a?(Array)
        raise InvalidInput, 'Labels must map outcomes and list findings'
      end
      raise InvalidInput, 'Every rule needs a label' unless label.fetch('outcomes').keys.sort == Rules::IDS
      unless label['outcomes'].values.all? do |value|
        %w[concern no_concern not_applicable inconclusive].include?(value)
      end
        raise InvalidInput, 'Unknown expected outcome'
      end
      raise InvalidInput, 'Label rationale required' if label.fetch('rationale').strip.empty?

      label.fetch('findings').each do |finding|
        raise InvalidInput, 'Each finding needs anchors' unless finding.is_a?(Hash) && finding['anchors'].is_a?(Array)
        unless label['outcomes'][finding.fetch('rule')] == 'concern'
          raise InvalidInput,
                'Finding rule must have concern outcome'
        end

        finding.fetch('anchors').each { |anchor| validate_anchor!(anchor, files) }
      end
    end

    def validate_anchor!(anchor, files)
      raise InvalidInput, 'Invalid expected anchor' unless anchor.is_a?(Hash)

      body = files[anchor.fetch('path')]
      line = anchor.fetch('line')
      raise InvalidInput, 'Invalid expected anchor' unless body && line.is_a?(Integer) && line.between?(1,
                                                                                                        body.lines.size)
    end

    def entry_for(id)
      cases.find { |item| item.fetch('id') == id } || raise(InvalidInput, 'Unknown case ID')
    end

    def validate_source_path!(path)
      return if path.is_a?(String) && !path.start_with?('/') && !path.split('/').intersect?(['', '.', '..'])

      raise InvalidInput,
            'Unsafe source path'
    end
  end
end
