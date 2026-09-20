# frozen_string_literal: true

require_relative '../slop_guard'

# The evaluation harness under SlopGuard::Eval: saved cases, scoring, repeat analysis and CI summaries.
# Product code does not depend on anything here.
%w[dataset runner analysis summary].each do |name|
  require_relative "eval/#{name}"
end
