# frozen_string_literal: true

# One way to stand in for Jev. `instance_double` verifies the `ask` signature against the real client, so a
# renamed or re-shaped provider method fails these specs instead of silently passing against a bare Object.
module StubClient
  def stub_client(&block)
    client = instance_double(SlopGuard::JevClient, model: 'stub-model')
    allow(client).to receive(:ask) { |state, questions| block.call(state, questions) }
    client
  end

  def silent_client
    instance_double(SlopGuard::JevClient, model: 'stub-model')
  end

  def fixture_dataset
    SlopGuard::Eval::Dataset.new(File.join(SlopGuard::ROOT, 'eval'))
  end

  def demo_profile
    SlopGuard::Profile.load('demo')
  end

  def ruby_profile
    SlopGuard::Profile.load('ruby')
  end

  def demo_rules
    SlopGuard::Rules.load(demo_profile.rules_dir)
  end

  def demo_snapshot(input)
    SlopGuard::Snapshot.build(input, profile: demo_profile)
  end
end

RSpec.configure { |config| config.include StubClient }
