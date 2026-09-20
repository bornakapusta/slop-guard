# frozen_string_literal: true

module SlopGuard
  # The trusted rule set of one profile with its content revision. `load` reads and validates a directory;
  # instances only hold the result.
  class Rules
    # The saved benchmark rule set. The evaluation harness validates labels against exactly these IDs.
    IDS = %w[G1 G2 G3 G4].freeze

    attr_reader :definitions, :revision, :files

    # Every `*.yml` directly inside the directory is a rule; its ID is the upper-cased file name. The revision
    # digests the parsed definitions in directory listing order.
    def self.load(directory = File.join(ROOT, 'config/rules'))
      files = Dir[File.join(directory, '*.yml')]
      raise InvalidInput, 'No rule files found' if files.empty?

      definitions = files.to_h do |path|
        rule = YAML.safe_load_file(path)
        raise InvalidInput, 'Each rule file must be a mapping' unless rule.is_a?(Hash)

        id = File.basename(path, '.yml').upcase
        Rule.validate!(id, rule)
        [id, rule]
      end
      new(definitions: definitions, files: files.map { |path| path.delete_prefix("#{ROOT}/") },
          revision: SlopGuard.digest(definitions))
    rescue KeyError, TypeError, ArgumentError, Psych::Exception, SystemCallError
      raise InvalidInput, 'Invalid rule configuration; expected g1.yml through g4.yml with valid thresholds'
    end

    def initialize(definitions:, files:, revision:)
      @definitions = definitions
      @files = files
      @revision = revision
    end

    def all
      definitions.map { |id, definition| Rule.new(id: id, definition: definition) }
    end

    def test_rule?(id)
      definitions.fetch(id).fetch('kind') == 'tests'
    end
  end
end
