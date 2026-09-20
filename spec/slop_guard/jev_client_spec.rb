# frozen_string_literal: true

RSpec.describe SlopGuard::JevClient do
  around do |example|
    Dir.mktmpdir do |directory|
      @directory = directory
      example.run
    end
  end
  let(:budget) { SlopGuard::Budget.new(ledger: File.join(@directory, 'ledger.jsonl')) }
  let(:client) { described_class.new(api_key: 'test-secret', budget: budget, sleeper: ->(_) {}) }
  let(:questions) { { 'q' => { 'type' => 'noul', 'instructions' => 'Is this covered?' } } }
  let(:payload) do
    { 'model' => described_class::MODEL, 'answers' => { 'q' => { 'type' => 'noul', 'noul' => 0.9 } },
      'usage' => { 'input_tokens' => 42, 'output_tokens' => 1 } }
  end

  def response(code, body, retry_after = nil)
    value = Net::HTTPResponse.new('1.1', code.to_s, 'test')
    value.body = body
    value['Retry-After'] = retry_after if retry_after
    # It is a completed response from the transport boundary.
    value.instance_variable_set(:@read, true)
    value
  end

  it 'serializes the pinned contract and validates probability and usage' do
    allow(client).to receive(:post) do |body|
      data = JSON.parse(body)
      expect(data).to eq('state' => 'source', 'model' => described_class::MODEL, 'questions' => questions)
      expect(body).not_to include('test-secret')
      response(200, JSON.generate(payload))
    end
    expect(client.ask('source', questions)).to eq('q' => 0.9)
    expect(budget.usage).to eq(42)
    expect(budget.attempts).to eq(1)
  end

  it 'rejects malformed JSON, wrong IDs, types, model and usage without leaking response content' do
    bad = [
      'secret-malformed-response',
      JSON.generate(payload.merge('model' => 'other')),
      JSON.generate(payload.merge('answers' => {})),
      JSON.generate(payload.merge('answers' => { 'q' => { 'type' => 'choice', 'noul' => 0.9 } })),
      JSON.generate(payload.merge('answers' => { 'q' => { 'type' => 'noul', 'noul' => 1.5 } })),
      JSON.generate(payload.merge('usage' => { 'input_tokens' => -1, 'output_tokens' => 0 }))
    ]
    bad.each do |body|
      allow(client).to receive(:post).and_return(response(200, body))
      expect { client.ask('source', questions) }.to raise_error(SlopGuard::ProviderError) { |error| expect(error.message).not_to include('secret-') }
    end
  end

  it 'does not retry bad credentials or invalid questions' do
    [401, 422].each do |code|
      expect(client).to receive(:post).once.and_return(response(code, 'private provider body'))
      expect { client.ask('source', questions) }.to raise_error(SlopGuard::ProviderError, "Jev returned HTTP #{code}")
    end
  end

  it 'bounds retryable failures and honors Retry-After' do
    sleeps = []
    subject = described_class.new(api_key: 'test', budget: budget, sleeper: ->(seconds) { sleeps << seconds })
    allow(subject).to receive(:post).and_return(response(429, '', '2'), response(529, '', '1'),
                                                response(200, JSON.generate(payload)))
    expect(subject.ask('source', questions)['q']).to eq(0.9)
    expect(sleeps).to eq([2.0, 1.0])
    expect(budget.attempts).to eq(3)
  end

  it 'keeps a reservation when transport usage is unknown' do
    allow(client).to receive(:post).and_raise(Net::ReadTimeout)
    expect { client.ask('source', questions) }.to raise_error(SlopGuard::ProviderError, /unknown/)
    expect(budget.reserved).to be_positive
    expect(budget.usage).to eq(0)
  end

  it 'rejects oversized evidence before dispatch and prevents unbounded retries' do
    expect(client).not_to receive(:post)
    expect { client.ask('x' * 30_000, questions) }.to raise_error(SlopGuard::LimitExceeded, /not truncated/)
    expect(budget.attempts).to eq(0)
    small = SlopGuard::Budget.new(ledger: File.join(@directory, 'small.jsonl'), max_attempts: 2)
    retrying = described_class.new(api_key: 'test', budget: small, sleeper: ->(_) {})
    expect(retrying).to receive(:post).twice.and_return(response(429, ''))
    expect { retrying.ask('source', questions) }.to raise_error(SlopGuard::LimitExceeded, /request budget/)
  end
end

RSpec.describe 'question batching' do
  it 'retains the same complete state in every batch and merges all answers' do
    Dir.mktmpdir do |directory|
      budget = SlopGuard::Budget.new(ledger: File.join(directory, 'ledger'))
      client = SlopGuard::JevClient.new(api_key: 'test', budget: budget)
      requests = []
      allow(client).to receive(:post) do |body|
        data = JSON.parse(body)
        requests << data
        expect(data['state']).to eq('x' * 24_000)
        expect(body.bytesize).to be <= 56 * 1024
        response = Net::HTTPOK.new('1.1', '200', 'OK')
        response.body = JSON.generate('model' => SlopGuard::JevClient::MODEL,
                                      'answers' => data['questions'].transform_values do
                                        { 'type' => 'noul', 'noul' => 0.1 }
                                      end,
                                      'usage' => { 'input_tokens' => 100, 'output_tokens' => 0 })
        response.instance_variable_set(:@read, true)
        response
      end
      questions = (1..100).to_h { |n| ["q#{n}", { 'type' => 'noul', 'instructions' => 'q' * 500 }] }
      expect(client.ask('x' * 24_000, questions).keys).to eq(questions.keys)
      expect(requests.size).to be > 1
    end
  end
end
