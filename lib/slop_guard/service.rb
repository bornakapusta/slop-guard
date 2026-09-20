# frozen_string_literal: true

require_relative '../slop_guard'

module SlopGuard
  # Hosted GitHub App adapter; the review engine also runs independently as a CLI.
  module Service
    class StaleReview < Error; end
    class PublicationUncertain < Error; end
  end
end

%w[settings store github_client github_source publisher worker webhook].each do |name|
  require_relative "service/#{name}"
end
