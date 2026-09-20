# frozen_string_literal: true

require_relative '../../support/service'

RSpec.describe SlopGuard::Service::Store do
  include_context 'app service'

  it 'refuses to reuse an existing data directory for another repository' do
    path = File.join(directory, 'bound.sqlite3')
    first = described_class.new(path, identity: [8, 7, 42])
    first.close
    expect { described_class.new(path, identity: [8, 7, 99]) }.to raise_error(SlopGuard::InvalidInput, /another/)
  end

  it 'persists queued work and deduplication across a database reopen' do
    store.receive('delivery', number: 1)
    other = described_class.new(File.join(directory, 'app.sqlite3'))
    expect(other.receive('delivery', number: 1)).to eq(:duplicate)
    expect(other.claim['pr']).to eq(1)
    expect(store.claim).to be_nil
  ensure
    other&.close
  end

  it 'recovers a crashed job without resetting its attempt count' do
    store.receive('delivery', number: 1)
    expect(store.claim['attempts']).to eq(1)
    store.recover
    expect(store.claim['attempts']).to eq(2)
  end

  it 'makes an in-progress job stale after a new delivery for that PR' do
    store.receive('first', number: 1)
    job = store.claim
    store.receive('second', number: 1)
    expect(store.current?(job)).to be(false)
  end

  it 'retains run and publication checkpoints on another connection' do
    store.begin_run('run-1', 1)
    store.evaluating('run-1')
    store.intend('review:run-1')
    other = described_class.new(File.join(directory, 'app.sqlite3'))
    expect(other.run('run-1')['phase']).to eq('evaluating')
    expect(other.publication('review:run-1')['attempted']).to eq(1)
  ensure
    other&.close
  end
end
