# frozen_string_literal: true

require 'bundler/setup'
require_relative '../lib/slop_guard/eval'

# Offline threshold replay over a saved live development report. The class lives in lib/slop_guard/eval.
begin
  unless ARGV.size == 2
    raise SlopGuard::InvalidInput,
          'Usage: ruby script/calibrate_thresholds.rb SOURCE_REPORT OUTPUT_REPORT'
  end

  source = JSON.parse(File.read(ARGV[0]))
  result = SlopGuard::ThresholdCalibration.new(source: source).run
  FileUtils.mkdir_p(File.dirname(ARGV[1]))
  File.write(ARGV[1], "#{JSON.pretty_generate(result)}\n")
  puts JSON.pretty_generate(result.fetch('rules').transform_values { |rule| rule.slice('baseline', 'best_replay') })
rescue SlopGuard::Error, Errno::ENOENT, JSON::ParserError => e
  warn SlopGuard.printable(e.message, keep_newlines: true)
  exit 2
end
