# frozen_string_literal: true

require 'base64'

module SlopGuard
  module Service
    # Reads immutable GitHub trees and blobs; target code is never executed.
    class GitHubSource
      attr_reader :profile

      def initialize(client:, settings:)
        @client = client
        @settings = settings
        @profile = YAML.safe_load_file(File.join(ROOT, 'config/repository.yml'))
      end

      def pull(number)
        result = @client.get("#{@client.repo_path}/pulls/#{Integer(number)}")
        unless result.dig('base', 'repo', 'id') == @settings.repository_id && result['number'] == number
          raise InvalidInput, 'Pull request repository identity does not match configuration'
        end

        sha(result.dig('base', 'sha'))
        sha(result.dig('head', 'sha'))
        result
      end

      def stamp(pull)
        SlopGuard.digest(pull.slice('number', 'state', 'draft', 'body').merge(
                           'base' => pull.dig('base', 'sha'), 'head' => pull.dig('head', 'sha')
                         ))
      end

      def snapshot(pull)
        Timeout.timeout(120, LimitExceeded, 'GitHub source collection deadline exceeded') do
          body = pull['body'].to_s
          raise LimitExceeded, 'PR body exceeds 16 KiB' if body.bytesize > 16_384

          base = sha(pull.dig('base', 'sha'))
          head = sha(pull.dig('head', 'sha'))
          inventory = @client.list("#{@client.repo_path}/pulls/#{pull['number']}/files")
          unless inventory.size == pull.fetch('changed_files') && inventory.size <= 50
            raise LimitExceeded, 'PR file inventory is incomplete or exceeds 50 changed files'
          end

          merge = @client.get("#{@client.repo_path}/compare/#{base}...#{head}")
          ancestor = sha(merge.dig('merge_base_commit', 'sha'))
          @bytes = 0
          @gaps = []
          @skipped = []
          @blobs = {}
          before = tree(ancestor)
          after = tree(head)
          result = Snapshot.new({ 'before' => before, 'files' => after, 'pr_body' => body,
                                  'source_gaps' => @gaps.uniq, 'skipped_paths' => @skipped.uniq,
                                  'source' => { 'base' => base, 'head' => head, 'merge_base' => ancestor } },
                                profile: profile)
          paths = inventory.flat_map { |file| file.values_at('filename', 'previous_filename') }.compact
          unless (result.changed.keys - paths).empty?
            raise InvalidInput,
                  'PR file inventory disagrees with source trees'
          end
          unless stamp(pull(pull['number'])) == stamp(pull)
            raise StaleReview,
                  'Pull request changed during source collection'
          end

          result
        end
      end

      private

      def sha(value)
        unless value.is_a?(String) && value.match?(/\A[0-9a-f]{40}\z/)
          raise InvalidInput,
                'Invalid GitHub commit or object ID'
        end

        value
      end

      def tree(commit)
        result = @client.get("#{@client.repo_path}/git/trees/#{commit}?recursive=1")
        raise LimitExceeded, 'GitHub tree is truncated' if result.fetch('truncated')

        entries = result.fetch('tree').select do |entry|
          path = entry.fetch('path')
          next false if entry['type'] == 'tree'

          permitted = profile.fetch('file_patterns').any? { |pattern| File.fnmatch?(pattern, path, File::FNM_PATHNAME) }
          @gaps << "Submodule was not inspected: #{path}" if entry['mode'] == '160000'
          @skipped << path unless permitted
          permitted
        end
        raise LimitExceeded, 'Repository exceeds 100 supported files per revision' if entries.size > 100

        entries.each_with_object({}) do |entry, files|
          path = entry.fetch('path')
          unless entry['type'] == 'blob' && %w[100644 100755].include?(entry['mode'])
            @gaps << "Non-regular file was not inspected: #{path}"
            next
          end
          raise LimitExceeded, 'Source file exceeds 16 KiB' if entry.fetch('size') > 16_384

          oid = sha(entry.fetch('sha'))
          files[path] = @blobs[oid] ||= blob(oid)
          @bytes += files[path].bytesize
          raise LimitExceeded, 'Source bundle exceeds 1 MiB' if @bytes > 1_048_576
        end
      end

      def blob(oid)
        result = @client.get("#{@client.repo_path}/git/blobs/#{oid}")
        raise InvalidInput, 'Unsupported GitHub blob encoding' unless result.fetch('encoding') == 'base64'

        body = Base64.strict_decode64(result.fetch('content').delete("\n")).force_encoding(Encoding::UTF_8)
        raise LimitExceeded, 'Source file exceeds 16 KiB' if body.bytesize > 16_384
        raise InvalidInput, 'Source blob is not valid text' unless body.valid_encoding? && !body.include?("\0")

        body
      rescue ArgumentError
        raise InvalidInput, 'Source blob is not valid base64'
      end
    end
  end
end
