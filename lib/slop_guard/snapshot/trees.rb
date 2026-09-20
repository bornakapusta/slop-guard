# frozen_string_literal: true

module SlopGuard
  class Snapshot
    # The permitted, bounded file trees of one review. Unsupported paths are listed, never sent. Oversized files
    # are dropped with a gap, matching the Git adapter.
    Trees = Data.define(:files, :before, :skipped) do
      def self.select(files, before, already_skipped, profile:, gaps:)
        validate!(files, before)
        skipped = ((files.keys | before.keys).reject { |path| profile.permitted?(path) } + already_skipped).uniq.sort
        files = files.select { |path, _| profile.permitted?(path) }
        before = before.select { |path, _| profile.permitted?(path) }
        oversized = (files.keys | before.keys).select do |path|
          [files[path], before[path]].compact.any? { |text| text.bytesize > Limits::FILE_BYTES }
        end
        oversized.each do |path|
          gaps << "File exceeds 16 KiB: #{path}"
          files.delete(path)
          before.delete(path)
        end
        gaps << "More than #{Limits::FILE_COUNT} files" if files.size > Limits::FILE_COUNT
        new(files: files, before: before, skipped: skipped)
      end

      def self.validate!(files, before)
        [files, before].each do |tree|
          raise InvalidInput, 'Invalid file inventory' unless tree.is_a?(Hash)

          tree.each do |path, text|
            raise InvalidInput, 'Unsafe source path' if SourcePath.unsafe?(path)
            raise InvalidInput, 'Invalid source encoding' unless SourceText.valid?(text)
          end
        end
      end
      private_class_method :validate!
    end
  end
end
