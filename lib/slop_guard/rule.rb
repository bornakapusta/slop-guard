# frozen_string_literal: true

module SlopGuard
  # One trusted rule: its ID and the parsed YAML definition exactly as loaded. The raw definition is what
  # `rules_revision` digests, so this class reads it and never rewrites it.
  class Rule < Data.define(:id, :definition)
    KINDS = %w[tests design].freeze
    SCENARIO_SOURCES = %w[behaviors failures].freeze
    CANDIDATE_KINDS = %w[method class].freeze

    def self.validate!(id, rule)
      unless rule.fetch('low').between?(0, 1) && rule.fetch('high').between?(0, 1) && rule['low'] < rule['high']
        raise InvalidInput, 'Invalid rule thresholds'
      end

      kind = rule.fetch('kind')
      raise InvalidInput, "Rule #{id} kind must be one of #{KINDS.join(', ')}" unless KINDS.include?(kind)

      kind == 'tests' ? validate_test_rule!(rule) : validate_design_rule!(rule)
    end

    def self.validate_test_rule!(rule)
      valid = text?(rule, %w[name applicable message correction missing]) &&
              SCENARIO_SOURCES.include?(rule.fetch('scenarios'))
      raise InvalidInput, 'Invalid rule configuration: missing questions or scenario source' unless valid
    end

    def self.validate_design_rule!(rule)
      candidates = rule.fetch('candidate')
      valid = text?(rule, %w[name applicable message correction global]) &&
              CANDIDATE_KINDS.include?(rule.fetch('candidate_kind')) &&
              candidates.is_a?(Hash) && !candidates.empty? &&
              candidates.all? { |key, value| key.is_a?(String) && value.is_a?(String) && !value.strip.empty? }
      %w[positive negative any_positive].each do |key|
        names = key == 'any_positive' ? rule.fetch(key, []) : rule.fetch(key)
        valid &&= names.is_a?(Array) && candidates.is_a?(Hash) && names.all? { |name| candidates.key?(name) }
        valid &&= !names.empty? unless key == 'any_positive'
      end
      raise InvalidInput, 'Invalid rule configuration: missing questions or candidate references' unless valid
    end

    def self.text?(rule, fields)
      fields.all? { |key| rule.fetch(key).is_a?(String) && !rule[key].strip.empty? }
    end
    private_class_method :validate_test_rule!, :validate_design_rule!, :text?

    def tests?
      definition.fetch('kind') == 'tests'
    end

    def high?(value)
      value >= definition.fetch('high')
    end

    def low?(value)
      value <= definition.fetch('low')
    end

    def thresholds
      definition.slice('high', 'low')
    end

    def fetch(...)
      definition.fetch(...)
    end
  end
end
