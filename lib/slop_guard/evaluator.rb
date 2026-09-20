# frozen_string_literal: true

require_relative 'evaluator/rule_result'
require_relative 'evaluator/rule_run'
require_relative 'evaluator/test_rule_run'
require_relative 'evaluator/design_rule_run'

module SlopGuard
  # Reconciles typed readings with rule thresholds and validated source anchors.
  class Evaluator
    REPORT_VERSION = 1

    attr_reader :client, :rules

    def initialize(client:, rules:)
      @client = client
      @rules = rules
    end

    # Safe to call repeatedly and concurrently: every review keeps its state in its own RuleRun objects.
    # After a provider or budget failure the remaining rules are not attempted: they would spend reservations on a
    # provider that just failed, and the review is already `failed`.
    def call(snapshot)
      failure = nil
      results = rules.all.to_h do |rule|
        if failure
          [rule.id, RuleResult.skipped(failure).to_h]
        else
          result = RuleRun.for(rule, snapshot: snapshot, client: client).call
          failure = result['error']
          [rule.id, result]
        end
      end
      { 'report_version' => REPORT_VERSION, 'snapshot' => snapshot.identity, 'version' => VERSION,
        'model' => client.model, 'rules_revision' => rules.revision, 'status' => status(results),
        'rules' => results, 'skipped_paths' => snapshot.skipped, 'source' => snapshot.source }
    end

    private

    def status(results)
      if results.values.any? { |value| value['error'] }
        'failed'
      elsif results.values.any? { |value| !value['gaps'].empty? }
        'incomplete'
      else
        'complete'
      end
    end
  end
end
