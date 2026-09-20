# frozen_string_literal: true

module SlopGuard
  # Trusted review configuration: which files are evidence, where the rule definitions live, and the Ruby/RSpec
  # conventions the evidence extractor relies on. Built once by the caller and passed to every component, so no
  # library class reads configuration from disk on its own.
  class Profile
    NAMES = { 'demo' => 'config/demo.yml', 'ruby' => 'config/repository.yml' }.freeze
    KNOWN_REQUIRES = %w[rspec simplecov colorize ipaddr stringio open3 tempfile rbconfig json set benchmark].freeze

    attr_reader :name, :file_patterns, :rules_dir

    # A profile name from NAMES, or a path to a YAML file with `file_patterns` and `rules_dir`.
    def self.load(name_or_path, rules_dir: nil)
      path = NAMES.fetch(name_or_path) { name_or_path }
      data = YAML.safe_load_file(File.expand_path(path, ROOT))
      raise InvalidInput, 'Profile must be a mapping with file_patterns and rules_dir' unless data.is_a?(Hash)

      new(name: NAMES.key(path) || File.basename(path, '.yml'),
          file_patterns: data.fetch('file_patterns'),
          rules_dir: File.expand_path(rules_dir || data.fetch('rules_dir'), ROOT))
    rescue KeyError, TypeError, Psych::Exception, SystemCallError
      raise InvalidInput, 'Invalid review profile; expected file_patterns and rules_dir'
    end

    def initialize(name:, file_patterns:, rules_dir:)
      unless file_patterns.is_a?(Array) && !file_patterns.empty? && file_patterns.all?(String)
        raise InvalidInput, 'Profile file_patterns must be a non-empty list of globs'
      end

      @name = name
      @file_patterns = file_patterns.freeze
      @rules_dir = rules_dir
    end

    def permitted?(path)
      file_patterns.any? { |pattern| File.fnmatch?(pattern, path, File::FNM_PATHNAME) }
    end

    # Ruby/RSpec conventions. A second language would supply its own answers here.
    def test_path?(path)
      path.start_with?('spec/')
    end

    def anchorable?(path)
      !test_path?(path) && (path.end_with?('.rb') || path.start_with?('bin/', 'exe/'))
    end

    def required_files
      ['spec/spec_helper.rb']
    end

    def known_requires
      KNOWN_REQUIRES
    end

    # Included in snapshot identities so two reviews with different evidence selection never share one.
    def to_h
      { 'name' => name, 'file_patterns' => file_patterns, 'rules_dir' => rules_dir.delete_prefix("#{ROOT}/") }
    end
  end
end
