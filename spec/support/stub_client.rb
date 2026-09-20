# frozen_string_literal: true

# One way to stand in for Jev. `instance_double` verifies the `ask` signature against the real client, so a
# renamed or re-shaped provider method fails these specs instead of silently passing against a bare Object.
module StubClient
  def stub_client(&block)
    client = instance_double(SlopGuard::JevClient)
    allow(client).to receive(:ask) { |state, questions| block.call(state, questions) }
    client
  end

  def fixture_dataset
    SlopGuard::Dataset.new(File.join(SlopGuard::ROOT, 'eval'))
  end
end

RSpec.configure { |config| config.include StubClient }
