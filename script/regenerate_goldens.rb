#!/usr/bin/env ruby
# frozen_string_literal: true

# Rewrites spec/fixtures/golden from the current code. Run it only when an output change is intended, and review
# the resulting diff: these files are the regression gate for behaviour-preserving refactors.
require 'bundler/setup'
require_relative '../lib/slop_guard'
require_relative '../lib/slop_guard/eval'
require_relative '../spec/support/goldens'

Goldens.write!
puts "Wrote #{Goldens.all.size} goldens to #{Goldens::DIRECTORY}"
