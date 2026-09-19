# frozen_string_literal: true

RSpec.describe SlopGuard::Budget do
  it 'preserves session reservations across new reviewer instances' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'ledger.jsonl')
      one = described_class.new(ledger: path, session_limit: described_class::RESERVATION)
      one.reserve!
      restarted = described_class.new(ledger: path, session_limit: described_class::RESERVATION)
      expect { restarted.reserve! }.to raise_error(SlopGuard::LimitExceeded, /session budget/)
    end
  end

  it 'enforces time and cost before allowing network work' do
    Dir.mktmpdir do |directory|
      clock = 0
      budget = described_class.new(ledger: File.join(directory, 'ledger'), seconds: 5, clock: -> { clock })
      clock = 6
      expect { budget.reserve! }.to raise_error(SlopGuard::LimitExceeded, /deadline/)
      budget = described_class.new(ledger: File.join(directory, 'ledger'), review_limit: 0)
      expect { budget.reserve! }.to raise_error(SlopGuard::LimitExceeded, /budget/)
    end
  end
end
