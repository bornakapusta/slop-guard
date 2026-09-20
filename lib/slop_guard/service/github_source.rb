# frozen_string_literal: true

require_relative 'github_source/tree_collection'

module SlopGuard
  module Service
    # Reads immutable GitHub trees and blobs; target code is never executed. Holds only the shared collaborators;
    # every `snapshot` collects its trees in its own TreeCollection.
    class GitHubSource
      COMMIT_SHA = /\A[0-9a-f]{40}\z/

      attr_reader :profile

      def self.sha(value)
        raise InvalidInput, 'Invalid GitHub commit or object ID' unless value.is_a?(String) && value.match?(COMMIT_SHA)

        value
      end

      def initialize(client:, settings:, profile: Profile.load('ruby'))
        @client = client
        @settings = settings
        @profile = profile
      end

      def pull(number)
        result = client.get("#{client.repo_path}/pulls/#{Integer(number)}")
        unless result.dig('base', 'repo', 'id') == settings.repository_id && result['number'] == number
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
          raise InputTooLarge, 'PR body exceeds 16 KiB' if body.bytesize > Limits::BODY_BYTES

          base = sha(pull.dig('base', 'sha'))
          head = sha(pull.dig('head', 'sha'))
          inventory = client.list("#{client.repo_path}/pulls/#{pull['number']}/files")
          unless inventory.size == pull.fetch('changed_files') && inventory.size <= Limits::CHANGED_FILES
            raise InputTooLarge, "PR file inventory is incomplete or exceeds #{Limits::CHANGED_FILES} changed files"
          end

          merge = client.get("#{client.repo_path}/compare/#{base}...#{head}")
          ancestor = sha(merge.dig('merge_base_commit', 'sha'))
          trees = TreeCollection.new(client: client, profile: profile).collect(before: ancestor, after: head)
          result = Snapshot.build({ 'before' => trees.before, 'files' => trees.after, 'pr_body' => body,
                                    'source_gaps' => trees.gaps.uniq, 'skipped_paths' => trees.skipped.uniq,
                                    'source' => { 'base' => base, 'head' => head, 'merge_base' => ancestor } },
                                  profile: profile)
          verify_inventory!(result, inventory)
          verify_unchanged!(pull)
          result
        end
      end

      private

      attr_reader :client, :settings

      def sha(value)
        self.class.sha(value)
      end

      def verify_inventory!(snapshot, inventory)
        paths = inventory.flat_map { |file| file.values_at('filename', 'previous_filename') }.compact
        return if (snapshot.changed.keys - paths).empty?

        raise InvalidInput, 'PR file inventory disagrees with source trees'
      end

      def verify_unchanged!(pull)
        return if stamp(pull(pull['number'])) == stamp(pull)

        raise StaleReview, 'Pull request changed during source collection'
      end
    end
  end
end
