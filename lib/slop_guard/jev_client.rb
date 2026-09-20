# frozen_string_literal: true

require 'net/http'

module SlopGuard
  # Sends bounded typed requests and validates the provider response contract.
  class JevClient
    MODEL = 'jev-1.13.0'
    ENDPOINT = URI('https://api.typesafe.ai/v1/systemone').freeze
    RETRYABLE = [429, 500, 502, 503, 504, 529].freeze
    attr_reader :budget

    def initialize(api_key:, budget:, sleeper: ->(seconds) { sleep(seconds) })
      raise ProviderError, 'TYPESAFE_API_KEY is not configured' if api_key.to_s.strip.empty?

      @api_key = api_key
      @budget = budget
      @sleeper = sleeper
    end

    def model
      MODEL
    end

    def ask(state, questions)
      state_bytes = JSON.generate(state).bytesize
      batches = []
      current = {}
      questions.each do |id, question|
        if state_bytes + JSON.generate(question).bytesize > 28 * 1024
          raise LimitExceeded, 'Model context byte limit exceeded; evidence was not truncated'
        end

        combined = current.merge(id => question)
        if JSON.generate('model' => MODEL, 'state' => state, 'questions' => combined).bytesize > 56 * 1024
          raise LimitExceeded, 'A question cannot fit the request byte limit' if current.empty?

          batches << current
          current = { id => question }
        else
          current = combined
        end
      end
      batches << current unless current.empty?
      batches.each_with_object({}) { |batch, answers| answers.merge!(ask_batch(state, batch)) }
    end

    private

    def ask_batch(state, questions)
      encoded = JSON.generate('model' => MODEL, 'state' => state, 'questions' => questions)
      loop do
        budget.reserve!
        begin
          response = post(encoded)
        rescue Timeout::Error, IOError, SystemCallError, OpenSSL::SSL::SSLError
          raise ProviderError, 'Jev transport failed; request usage is unknown'
        end
        code = response.code.to_i
        if RETRYABLE.include?(code)
          wait = retry_delay(response['Retry-After'])
          raise LimitExceeded, 'Retry would exceed review deadline' if wait >= budget.remaining

          @sleeper.call(wait)
          next
        end
        raise ProviderError, "Jev returned HTTP #{code}" unless code == 200

        return validate(response.body, questions)
      end
    end

    def post(body)
      request = Net::HTTP::Post.new(ENDPOINT)
      request['Authorization'] = "Bearer #{@api_key}"
      request['Content-Type'] = 'application/json'
      request.body = body
      http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
      http.use_ssl = true
      http.open_timeout = [5, budget.remaining].min
      http.read_timeout = [30, budget.remaining].min
      http.write_timeout = [10, budget.remaining].min
      http.max_retries = 0
      response = nil
      Timeout.timeout(budget.remaining, LimitExceeded, 'Review deadline exceeded') do
        http.request(request) do |incoming|
          response = incoming
          data = +''
          incoming.read_body do |chunk|
            data << chunk
            raise ProviderError, 'Jev response exceeds 128 KiB' if data.bytesize > 131_072
            raise LimitExceeded, 'Review deadline exceeded' unless budget.remaining.positive?
          end
          incoming.body = data
        end
      end
      response
    end

    def validate(body, questions)
      data = JSON.parse(body)
      raise ProviderError, 'Jev returned an unexpected model' unless data.fetch('model') == MODEL

      answers = data.fetch('answers')
      unless answers.is_a?(Hash) && answers.keys.sort == questions.keys.sort
        raise ProviderError,
              'Jev answer IDs do not match questions'
      end

      values = answers.to_h do |id, answer|
        value = answer.fetch('noul')
        unless answer.fetch('type') == 'noul' && value.is_a?(Numeric) && value.finite? && value.between?(0, 1)
          raise ProviderError, 'Jev returned an invalid probability'
        end

        [id, value]
      end
      usage = data.fetch('usage')
      %w[input_tokens output_tokens].each do |key|
        raise ProviderError, 'Jev returned invalid usage' unless usage[key].is_a?(Integer) && usage[key] >= 0
      end
      budget.record_usage(usage['input_tokens'])
      raise LimitExceeded, 'Review deadline exceeded' unless budget.remaining.positive?

      values
    rescue JSON::ParserError, KeyError, NoMethodError, TypeError
      raise ProviderError, 'Jev returned a malformed response'
    end

    def retry_delay(header)
      return 1.0 if header.nil?

      seconds = Float(header, exception: false)
      seconds ||= Time.httpdate(header) - Time.now
      [seconds, 0.0].max
    rescue ArgumentError
      1.0
    end
  end
end
