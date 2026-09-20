# frozen_string_literal: true

require 'diff/lcs'

module SlopGuard
  class Snapshot
    # Changed line numbers in the head tree, per path, for every path that differs between the two trees.
    module Changes
      def self.diff(before, files)
        (before.keys | files.keys).sort.each_with_object({}) do |path, result|
          next if before[path] == files[path]

          old_lines = before.fetch(path, '').lines
          new_lines = files.fetch(path, '').lines
          result[path] = Diff::LCS.sdiff(old_lines, new_lines).filter_map do |change|
            next if change.unchanged?

            change.new_element ? change.new_position + 1 : nil
          end.uniq
        end
      end
    end
  end
end
