# frozen_string_literal: true

# Exercises JevClient#post through an injected connection instead of stubbing the private method.
RSpec.describe SlopGuard::JevClient, 'transport' do
  around do |example|
    Dir.mktmpdir do |directory|
      @directory = directory
      example.run
    end
  end

  let(:clock) { [0.0] }
  let(:budget) do
    SlopGuard::Budget.new(ledger: File.join(@directory, 'ledger.jsonl'), seconds: 120, clock: -> { clock[0] })
  end
  let(:questions) { { 'q' => { 'type' => 'noul', 'instructions' => 'Is this covered?' } } }
  let(:payload) do
    JSON.generate('model' => described_class::MODEL, 'answers' => { 'q' => { 'type' => 'noul', 'noul' => 0.9 } },
                  'usage' => { 'input_tokens' => 42, 'output_tokens' => 1 })
  end

  def client_with(*responses, random: Random.new(1))
    connection = FakeConnection.new(responses)
    [described_class.new(api_key: 'test', budget: budget, sleeper: ->(_) {}, random: random, http: connection),
     connection]
  end

  it 'reuses one started connection across requests and clamps timeouts to the remaining deadline' do
    client, connection = client_with(ChunkedResponse.new(200, [payload]), ChunkedResponse.new(200, [payload]))
    clock[0] = 100.0
    client.ask('state', questions)
    client.ask('state', questions)
    expect(connection.starts).to eq(1)
    expect(connection.requests.size).to eq(2)
    expect(connection.read_timeout).to eq(20.0)
    expect(connection.write_timeout).to eq(10)
    expect(connection.requests.first['Authorization']).to eq('Bearer test')
  end

  it 'stops reading a body above 128 KiB and drops the connection' do
    client, connection = client_with(ChunkedResponse.new(200, ['x' * 70_000, 'y' * 70_000]))
    expect { client.ask('state', questions) }.to raise_error(SlopGuard::ProviderError, /128 KiB/)
    expect(connection.finishes).to eq(1)
    expect(budget.attempts).to eq(1)
  end

  it 'aborts a slow body when the deadline passes and never treats a zero timeout as infinite' do
    response = ChunkedResponse.new(200, %w[a b])
    client, = client_with(response)
    allow(response).to receive(:read_body).and_wrap_original do |original, &block|
      original.call do |chunk|
        clock[0] = 121.0 if chunk == 'a'
        block.call(chunk)
      end
    end
    expect { client.ask('state', questions) }.to raise_error(SlopGuard::LimitExceeded, /deadline/)
    clock[0] = 119.9995
    expect(client.send(:clamp, 5)).to eq(0.001)
  end

  it 'backs off exponentially with jitter when no Retry-After header is present' do
    sleeps = []
    connection = FakeConnection.new([ChunkedResponse.new(503, ['']), ChunkedResponse.new(503, ['']),
                                     ChunkedResponse.new(200, [payload])])
    client = described_class.new(api_key: 'test', budget: budget, sleeper: ->(s) { sleeps << s },
                                 random: Random.new(7), http: connection)
    expect(client.ask('state', questions)).to eq('q' => 0.9)
    expect(sleeps.size).to eq(2)
    expect(sleeps[0]).to be_between(0.5, 1.0)
    expect(sleeps[1]).to be_between(1.0, 2.0)
  end

  it 'reports transport errors without usage and resets the connection' do
    client, connection = client_with(EOFError.new('stale keep-alive'))
    expect { client.ask('state', questions) }.to raise_error(SlopGuard::ProviderError, /unknown/)
    expect(connection.finishes).to eq(1)
    expect(budget.reserved).to be_positive
  end

  it 'encodes the state once and batches by a running byte count' do
    state = 'x' * 20_000
    calls = 0
    allow(JSON).to receive(:generate).and_wrap_original do |original, value|
      calls += 1 if value.equal?(state)
      original.call(value)
    end
    responses = Array.new(6) do
      ChunkedResponse.new(200, [JSON.generate('model' => described_class::MODEL, 'answers' => {},
                                              'usage' => { 'input_tokens' => 1, 'output_tokens' => 0 })])
    end
    connection = FakeConnection.new(responses)
    allow(connection).to receive(:request).and_wrap_original do |original, request, &block|
      data = JSON.parse(request.body)
      expect(request.body.bytesize).to be <= described_class::MAX_REQUEST_BYTES
      body = JSON.generate('model' => described_class::MODEL,
                           'answers' => data['questions'].transform_values { { 'type' => 'noul', 'noul' => 0.2 } },
                           'usage' => { 'input_tokens' => 1, 'output_tokens' => 0 })
      original.call(request) { |_| block.call(ChunkedResponse.new(200, [body])) }
    end
    client = described_class.new(api_key: 'test', budget: budget, sleeper: ->(_) {}, http: connection)
    many = (1..80).to_h { |n| ["q#{n}", { 'type' => 'noul', 'instructions' => 'q' * 600 }] }
    expect(client.ask(state, many).keys).to eq(many.keys)
    expect(connection.requests.size).to be > 1
    expect(calls).to eq(1)
  end
end
