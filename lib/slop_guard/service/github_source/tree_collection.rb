# frozen_string_literal: true

require 'base64'

module SlopGuard
  module Service
    class GitHubSource
      # Collects the permitted blobs of two revisions under one byte budget, sharing fetched blobs between them.
      # Used for one snapshot and discarded.
      class TreeCollection
        Trees = Data.define(:before, :after, :gaps, :skipped)

        BLOB_MODES = %w[100644 100755].freeze

        def initialize(client:, profile:)
          @client = client
          @profile = profile
          @bytes = 0
          @gaps = []
          @skipped = []
          @blobs = {}
        end

        def collect(before:, after:)
          before_tree = tree(before)
          after_tree = tree(after)
          Trees.new(before: before_tree, after: after_tree, gaps: gaps, skipped: skipped)
        end

        private

        attr_reader :client, :profile, :gaps, :skipped, :blobs

        def tree(commit)
          result = client.get("#{client.repo_path}/git/trees/#{commit}?recursive=1")
          raise LimitExceeded, 'GitHub tree is truncated' if result.fetch('truncated')

          entries = result.fetch('tree').select do |entry|
            path = entry.fetch('path')
            next false if entry['type'] == 'tree'

            permitted = profile.permitted?(path)
            gaps << "Submodule was not inspected: #{path}" if entry['mode'] == '160000'
            skipped << path unless permitted
            permitted
          end
          if entries.size > Limits::FILE_COUNT
            raise InputTooLarge, "Repository exceeds #{Limits::FILE_COUNT} supported files per revision"
          end

          entries.each_with_object({}) do |entry, files|
            path = entry.fetch('path')
            unless entry['type'] == 'blob' && BLOB_MODES.include?(entry['mode'])
              gaps << "Non-regular file was not inspected: #{path}"
              next
            end
            raise InputTooLarge, 'Source file exceeds 16 KiB' if entry.fetch('size') > Limits::FILE_BYTES

            oid = GitHubSource.sha(entry.fetch('sha'))
            files[path] = blobs[oid] ||= blob(oid)
            @bytes += files[path].bytesize
            raise InputTooLarge, 'Source bundle exceeds 1 MiB' if @bytes > Limits::BUNDLE_BYTES
          end
        end

        def blob(oid)
          result = client.get("#{client.repo_path}/git/blobs/#{oid}")
          raise InvalidInput, 'Unsupported GitHub blob encoding' unless result.fetch('encoding') == 'base64'

          body = Base64.strict_decode64(result.fetch('content').delete("\n")).force_encoding(Encoding::UTF_8)
          raise InputTooLarge, 'Source file exceeds 16 KiB' if body.bytesize > Limits::FILE_BYTES
          raise InvalidInput, 'Source blob is not valid text' unless body.valid_encoding? && !body.include?("\0")

          body
        rescue ArgumentError
          raise InvalidInput, 'Source blob is not valid base64'
        end
      end
    end
  end
end
