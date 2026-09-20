# frozen_string_literal: true

RSpec.describe SlopGuard::Budget do
  it 'preserves session reservations across new reviewer instances' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'ledger.jsonl')
      one = described_class.open(ledger: path, session_limit: described_class::RESERVATION)
      one.reserve!
      restarted = described_class.open(ledger: path, session_limit: described_class::RESERVATION)
      expect { restarted.reserve! }.to raise_error(SlopGuard::LimitExceeded, /session budget/)
    end
  end

  it 'fails closed on a corrupt ledger instead of contacting the provider' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'ledger.jsonl')
      File.write(path, "{\"reserved_usd\":0.001}\ngarbage\n")
      budget = described_class.open(ledger: path)
      expect { budget.reserve! }.to raise_error(SlopGuard::InvalidInput, /ledger is corrupt/)
      File.write(path, "[1,2]\n")
      expect { budget.reserve! }.to raise_error(SlopGuard::InvalidInput, /ledger is corrupt/)
      File.write(path, "{\"reserved_usd\":\"lots\"}\n")
      client = SlopGuard::JevClient.new(api_key: 'test', budget: budget, sleeper: ->(_) {})
      expect(client).not_to receive(:post)
      question = { 'q' => { 'type' => 'noul', 'instructions' => 'x' } }
      expect { client.ask('state', question) }.to raise_error(SlopGuard::InvalidInput, /ledger is corrupt/)
      expect(budget.attempts).to eq(0)
    end
  end

  it 'allows a reservation that exactly reaches the review limit and records token usage' do
    Dir.mktmpdir do |directory|
      budget = described_class.open(ledger: File.join(directory, 'ledger'),
                                    review_limit: described_class::RESERVATION * 2)
      2.times { budget.reserve! }
      expect(budget.attempts).to eq(2)
      expect { budget.reserve! }.to raise_error(SlopGuard::LimitExceeded, /request budget/)
      budget.record_usage(40)
      budget.record_usage(2)
      expect(budget.usage).to eq(42)
    end
  end

  it 'enforces time and cost before allowing network work' do
    Dir.mktmpdir do |directory|
      clock = 0
      budget = described_class.open(ledger: File.join(directory, 'ledger'), seconds: 5, clock: -> { clock })
      clock = 6
      expect { budget.reserve! }.to raise_error(SlopGuard::LimitExceeded, /deadline/)
      budget = described_class.open(ledger: File.join(directory, 'ledger'), review_limit: 0)
      expect { budget.reserve! }.to raise_error(SlopGuard::LimitExceeded, /budget/)
    end
  end
end
