# frozen_string_literal: true

module SlopGuard
  # A validated head-side source location. `to_h` is the report shape: String keys in schema order.
  Anchor = Data.define(:path, :line, :side) do
    def to_h
      { 'path' => path, 'line' => line, 'side' => side }
    end
  end

  # One advisory finding of a rule. Built inside a rule run and converted with `to_h` at the report boundary, so
  # scoring, rendering and JSON all read the same String keys in `docs/report-schema.md` order.
  Finding = Data.define(:id, :rule, :severity, :topic, :anchor, :readings, :thresholds, :message, :correction,
                        :scenario) do
    # Stable across repeats and readings, so publishers update rather than duplicate comments. Key order and the
    # `nil` scenario of a design finding are part of the digest.
    def self.id_for(rule:, topic:, scenario:, path:)
      SlopGuard.digest('rule' => rule, 'topic' => topic, 'scenario' => scenario, 'path' => path)
    end

    def to_h
      { 'id' => id, 'rule' => rule, 'severity' => severity, 'topic' => topic, 'anchor' => anchor.to_h,
        'readings' => readings, 'thresholds' => thresholds, 'message' => message, 'correction' => correction,
        'scenario' => scenario }
    end
  end
end
