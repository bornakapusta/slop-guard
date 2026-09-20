# frozen_string_literal: true

require 'open3'
require 'timeout'

module SlopGuard
  # Reads immutable local Git objects, without checking out or executing target code.
  class GitSource
    attr_reader :profile, :metadata

    def initialize(repository:, base:, head: 'HEAD')
      @repository = File.realpath(repository)
      @base_ref = base
      @head_ref = head
      @profile = YAML.safe_load_file(File.join(ROOT, 'config/repository.yml'))
      @metadata = {}
    rescue Errno::ENOENT, Errno::ENOTDIR
      raise InvalidInput, 'Repository directory does not exist'
    end

    def input(pr_body:)
      raise InvalidInput, 'Expected behavior text exceeds 16 KiB' if pr_body.bytesize > 16_384
      raise InvalidInput, 'Expected behavior text must be UTF-8' unless pr_body.valid_encoding?

      base = revision(@base_ref)
      head = revision(@head_ref)
      ancestors = git('merge-base', '--all', base, head).split
      raise InvalidInput, 'Expected one merge base; fetch sufficient local history' unless ancestors.size == 1

      @metadata = { 'kind' => 'local_git', 'base' => base, 'head' => head, 'merge_base' => ancestors.first }
      @gaps = []
      @skipped = []
      @bytes = 0
      before = tree(ancestors.first)
      after = tree(head)
      { 'before' => before, 'files' => after, 'pr_body' => pr_body,
        'source_gaps' => @gaps.uniq, 'skipped_paths' => @skipped.uniq.sort, 'source' => metadata }
    rescue ArgumentError, Encoding::CompatibilityError
      raise InvalidInput, 'Repository paths and expectation text must use valid UTF-8'
    end

    private

    def revision(ref)
      raise InvalidInput, 'A non-option Git revision is required' if ref.to_s.empty? || ref.start_with?('-')

      git('rev-parse', '--verify', '--end-of-options', "#{ref}^{commit}").strip
    end

    def tree(revision)
      entries = git('ls-tree', '-r', '-l', '-z', '--full-tree', revision).split("\0")
      selected = entries.filter_map do |entry|
        header, path = entry.split("\t", 2)
        mode, type, oid, size = header.split
        unless path&.valid_encoding? && !path.start_with?('/') &&
               !path.split('/').intersect?(['', '.', '..'])
          raise InvalidInput, 'Invalid Git tree path'
        end

        if mode == '160000'
          @gaps << "Submodule was not inspected: #{path}"
          next
        end
        unless profile.fetch('file_patterns').any? { |pattern| File.fnmatch?(pattern, path, File::FNM_PATHNAME) }
          @skipped << path
          next
        end
        unless type == 'blob' && %w[100644 100755].include?(mode)
          @gaps << "Non-regular file was not inspected: #{path}"
          next
        end
        raise LimitExceeded, "Source file exceeds 16 KiB: #{path}" if size.to_i > 16_384

        [path, oid]
      end
      raise LimitExceeded, 'Repository exceeds 100 supported files per revision' if selected.size > 100

      selected.to_h do |path, oid|
        body = git('cat-file', 'blob', oid, limit: 16_384)
        raise InvalidInput, "Source must be UTF-8 text: #{path}" unless body.valid_encoding? && !body.include?("\0")

        @bytes += body.bytesize
        raise LimitExceeded, 'Source bundle exceeds 1 MiB' if @bytes > 1_048_576

        [path, body]
      end
    end

    def git(*arguments, limit: 4 * 1024 * 1024)
      # Ignore inherited Git overrides and never fetch missing partial-clone objects.
      environment = ENV.keys.grep(/\AGIT_/).to_h { |key| [key, nil] }.merge(
        'GIT_CONFIG_NOSYSTEM' => '1', 'GIT_CONFIG_GLOBAL' => File::NULL,
        'GIT_TERMINAL_PROMPT' => '0', 'GIT_NO_LAZY_FETCH' => '1'
      )
      output = +''
      Open3.popen2e(environment, 'git', '--no-optional-locks', '--no-replace-objects',
                    '-C', @repository, *arguments, pgroup: true) do |stdin, stream, process|
        stdin.close
        begin
          Timeout.timeout(10, LimitExceeded, 'Local Git command timed out') do
            loop do
              output << stream.readpartial(16_384)
              raise LimitExceeded, 'Local Git output exceeds its byte limit' if output.bytesize > limit
            rescue EOFError
              break
            end
            unless process.value.success?
              raise InvalidInput,
                    "Local Git #{arguments.first} failed; check repository, revisions and local history"
            end
          end
        ensure
          if process.alive?
            begin
              Process.kill('KILL', -process.pid)
            rescue Errno::ESRCH
              nil
            end
          end
        end
      end
      output.force_encoding(Encoding::UTF_8)
    rescue Errno::ENOENT
      raise InvalidInput, 'Git executable is unavailable'
    end
  end
end
