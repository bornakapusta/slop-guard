# frozen_string_literal: true

require_relative '../slop_guard'

# The evaluation harness: saved cases, scoring, repeat analysis, CI summaries and threshold replay.
# Product code does not depend on anything here.
%w[dataset runner analysis summary].each do |name|
  require_relative "eval/#{name}"
end
