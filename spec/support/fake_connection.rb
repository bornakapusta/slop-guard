# frozen_string_literal: true

# Minimal Net::HTTP stand-in for JevClient transport specs: yields scripted responses and records the
# connection lifecycle, so `post` is exercised without a network or a stubbed private method.
class FakeConnection
  attr_accessor :open_timeout, :read_timeout, :write_timeout
  attr_reader :requests, :starts, :finishes

  def initialize(responses)
    @responses = responses
    @requests = []
    @starts = 0
    @finishes = 0
    @started = false
  end

  def started? = @started

  def start
    @started = true
    @starts += 1
  end

  def finish
    @started = false
    @finishes += 1
  end

  def request(request, &block)
    @requests << request
    response = @responses.shift
    raise response if response.is_a?(Exception)

    block.call(response)
    response
  end
end

# A streamed response body delivered in chunks.
class ChunkedResponse
  attr_accessor :body
  attr_reader :code

  def initialize(code, chunks, headers = {})
    @code = code.to_s
    @chunks = chunks
    @headers = headers
  end

  def [](name) = @headers[name]

  def read_body(&)
    @chunks.each(&)
  end
end
