# frozen_string_literal: true

require 'base64'

module SlopGuard
  module Service
    class GitHubSource
      # Collects the permitted blobs of two revisions under one byte budget, sharing fetched blobs between them.
      # Used for one snapshot and discarded. Unlike the local adapter, an oversized file is a hard error here.
      class TreeCollection
        Trees = Data.define(:before, :after, :gaps, :skipped)

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

          kept = entries(result).filter_map do |entry, kind|
            case kind
            when :submodule then gaps << "Submodule was not inspected: #{entry.path}"
            when :skipped then skipped << entry.path
            else next [entry, kind]
            end
            nil
          end
          if kept.size > Limits::FILE_COUNT
            raise InputTooLarge, "Repository exceeds #{Limits::FILE_COUNT} supported files per revision"
          end

          kept.each_with_object({}) { |(entry, kind), files| read(entry, kind, files) }
        end

        # Directories are listing structure, not files, and are never counted or reported.
        def entries(result)
          result.fetch('tree').filter_map do |raw|
            next if raw['type'] == 'tree'

            entry = TreeEntry.new(path: raw.fetch('path'), mode: raw['mode'], type: raw['type'], size: raw['size'],
                                  oid: raw['sha'])
            [entry, entry.classify(profile)]
          end
        end

        def read(entry, kind, files)
          case kind
          when :non_regular then gaps << "Non-regular file was not inspected: #{entry.path}"
          when :oversized then raise InputTooLarge, 'Source file exceeds 16 KiB'
          else
            oid = GitHubSource.sha(entry.oid)
            files[entry.path] = blobs[oid] ||= blob(oid)
            @bytes += files[entry.path].bytesize
            raise InputTooLarge, 'Source bundle exceeds 1 MiB' if @bytes > Limits::BUNDLE_BYTES
          end
        end

        def blob(oid)
          result = client.get("#{client.repo_path}/git/blobs/#{oid}")
          raise InvalidInput, 'Unsupported GitHub blob encoding' unless result.fetch('encoding') == 'base64'

          body = Base64.strict_decode64(result.fetch('content').delete("\n")).force_encoding(Encoding::UTF_8)
          raise InputTooLarge, 'Source file exceeds 16 KiB' if body.bytesize > Limits::FILE_BYTES
          raise InvalidInput, 'Source blob is not valid text' unless SourceText.valid?(body)

          body
        rescue ArgumentError
          raise InvalidInput, 'Source blob is not valid base64'
        end
      end
    end
  end
end
