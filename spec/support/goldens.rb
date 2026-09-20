# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'stringio'

# Byte-for-byte snapshots of the offline outputs a refactor must not change. The saved text is compared as a
# string, never as a parsed Hash: Hash#== ignores key order and a Symbol key silently differs from its String.
module Goldens
  DIRECTORY = File.join(SlopGuard::ROOT, 'spec/fixtures/golden')
  # Fixed provider answers for one g1-violation review per outcome. `covered` makes the coverage evidence
  # conflict; `fail_design` raises on the first rule after G1 so G1's finding is preserved in a failed report.
  OUTCOMES = { 'concern' => {}, 'inconclusive' => { covered: true }, 'failed' => { fail_design: true } }.freeze

  # A provider double usable outside RSpec (the regeneration script). Records every ask for fingerprint checks.
  class FixedClient
    attr_reader :asks

    def initialize(covered:, fail_design:)
      @covered = covered
      @fail_design = fail_design
      @asks = []
    end

    def model
      'stub-model'
    end

    def ask(state, questions)
      @asks << [state, questions]
      scenarios = questions.keys.any? { |id| id.end_with?('/missing') }
      raise SlopGuard::ProviderError, 'Jev unavailable' if @fail_design && !scenarios

      questions.to_h { |id, _| [id, answer(id.split('/').last, scenarios)] }
    end

    private

    def answer(key, scenarios)
      case key
      when 'clear', 'missing' then 0.95
      when 'applicable' then scenarios ? 0.95 : 0.05
      else key.start_with?('exercise_', 'assert_') && @covered ? 0.95 : 0.05
      end
    end
  end

  module_function

  def all
    renders = {}
    dataset.cases.each { |entry| renders["inspect/#{entry['id']}.json"] = -> { cli(entry['id'], '--inspect') } }
    %w[demo ruby].each { |name| renders["show-rules/#{name}.json"] = -> { cli('--show-rules', '--profile', name) } }
    renders['evaluate-validate.json'] = -> { validate }
    OUTCOMES.each do |outcome, options|
      renders["review/#{outcome}.json"] = -> { JSON.pretty_generate(review(**options)) }
      renders["review/#{outcome}.md"] = -> { SlopGuard::Report.markdown(review(**options)) }
    end
    renders
  end

  def saved
    Dir[File.join(DIRECTORY, '**/*.{json,md}')].map { |path| path.delete_prefix("#{DIRECTORY}/") }.sort
  end

  def write!
    all.each do |name, render|
      path = File.join(DIRECTORY, name)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, render.call)
    end
  end

  def read(name)
    File.read(File.join(DIRECTORY, name))
  end

  def cli(*argv)
    stdout = StringIO.new
    status = SlopGuard::CLI.new(stdout: stdout, stderr: StringIO.new, stdin: StringIO.new,
                                env: { 'TYPESAFE_API_KEY' => '' }).run(argv)
    raise "bin/review #{argv.join(' ')} exited #{status}" unless status.zero?

    stdout.string
  end

  def validate
    stdout, stderr, status = Open3.capture3({ 'TYPESAFE_API_KEY' => '' }, RbConfig.ruby, 'bin/evaluate',
                                            '--validate', chdir: SlopGuard::ROOT)
    raise "bin/evaluate --validate exited #{status.exitstatus}: #{stderr}" unless status.success?

    stdout
  end

  def review(covered: false, fail_design: false, client: fixed_client(covered: covered, fail_design: fail_design))
    SlopGuard::Evaluator.new(client: client, rules: SlopGuard::Rules.load).call(snapshot)
  end

  def fixed_client(covered: false, fail_design: false)
    FixedClient.new(covered: covered, fail_design: fail_design)
  end

  def snapshot
    SlopGuard::Snapshot.build(dataset.input('g1-violation'), profile: SlopGuard::Profile.load('demo'))
  end

  def dataset
    SlopGuard::Eval::Dataset.new(File.join(SlopGuard::ROOT, 'eval'))
  end
end
