# frozen_string_literal: true

require 'bundler/setup'
require_relative '../lib/slop_guard/eval'

# Renders the CI job summary for a development evaluation directory. The class lives in lib/slop_guard/eval.
begin
  unless ARGV.size == 2
    raise SlopGuard::InvalidInput,
          'Usage: ruby script/evaluation_summary.rb DIRECTORY EXIT_STATUS'
  end

  paths = Dir[File.join(ARGV[0], '*', 'report.json')]
  unless paths.one?
    raise SlopGuard::InvalidInput,
          'Evaluation did not produce exactly one report; inspect execution logs'
  end

  # Includes runs appended after the last checkpoint, so a timed-out job still reports every finished review.
  report = SlopGuard::EvalRunner.load(File.dirname(paths.first))
  ledger = File.join(File.dirname(paths.first), 'requests.jsonl')
  raise SlopGuard::InvalidInput, 'Request ledger is missing' unless File.file?(ledger)

  reservations = File.readlines(ledger).map { |line| JSON.parse(line).fetch('reserved_usd') }
  unless reservations.all? { |value| value.is_a?(Numeric) && value.finite? && value >= 0 }
    raise SlopGuard::InvalidInput, 'Request ledger contains invalid reservations'
  end

  ids = SlopGuard::Dataset.new(File.join(SlopGuard::ROOT, 'eval')).cases('development').map { |entry| entry.fetch('id') }
  summary = SlopGuard::EvaluationSummary.new(report: report, case_ids: ids, reserved: reservations.sum,
                                             exit_status: Integer(ARGV[1]))
  puts summary.markdown
  exit 1 unless summary.status == 'PASSED DEVELOPMENT LABELS'
rescue SlopGuard::Error, JSON::ParserError, KeyError, ArgumentError, SystemCallError => e
  puts "## Jev development evaluation\n\n**REPORT UNAVAILABLE:** #{SlopGuard::Report.escape(e.message)}"
  exit 2
end
