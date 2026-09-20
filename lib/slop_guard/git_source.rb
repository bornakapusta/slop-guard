# frozen_string_literal: true

require 'open3'

module SlopGuard
  # Reads immutable local Git objects, without checking out or executing target code.
  class GitSource
    Tree = Data.define(:files, :gaps, :skipped)

    OUTPUT_LIMIT = 4 * 1024 * 1024
    STDERR_LIMIT = 4096
    TIMEOUT_SECONDS = 10
    BLOB_MODES = %w[100644 100755].freeze
    # Plumbing only. Repository-local config is still read, so protocol handlers and the filesystem monitor hook
    # are disabled explicitly; global and system config are dropped through the environment.
    GIT_OPTIONS = ['--no-optional-locks', '--no-replace-objects',
                   '-c', 'protocol.allow=never', '-c', 'core.fsmonitor=false'].freeze

    attr_reader :profile, :metadata

    def initialize(repository:, base:, head: 'HEAD')
      @repository = File.realpath(repository)
      @base_ref = base
      @head_ref = head
      @profile = YAML.safe_load_file(File.join(ROOT, 'config/repository.yml'))
      @metadata = {}
      @environment = scrubbed_environment
    rescue Errno::ENOENT, Errno::ENOTDIR
      raise InvalidInput, 'Repository directory does not exist'
    end

    def input(pr_body:)
      raise InvalidInput, 'Expected behavior text exceeds 16 KiB' if pr_body.bytesize > 16_384
      raise InvalidInput, 'Expected behavior text must be UTF-8' unless pr_body.valid_encoding?

      verify_root!
      base = revision(@base_ref)
      head = revision(@head_ref)
      ancestors = git('merge-base', '--all', base, head).split
      raise InvalidInput, 'Expected one merge base; fetch sufficient local history' unless ancestors.size == 1

      @metadata = { 'kind' => 'local_git', 'base' => base, 'head' => head, 'merge_base' => ancestors.first }
      before = tree(ancestors.first)
      after = tree(head)
      { 'before' => before.files, 'files' => after.files, 'pr_body' => pr_body,
        'source_gaps' => (before.gaps + after.gaps).uniq,
        'skipped_paths' => (before.skipped + after.skipped).uniq.sort, 'source' => metadata }
    rescue ArgumentError, Encoding::CompatibilityError
      raise InvalidInput, 'Repository paths and expectation text must use valid UTF-8'
    end

    private

    def verify_root!
      top = File.realpath(git('rev-parse', '--show-toplevel').strip)
      return if top == @repository

      raise InvalidInput, 'Pass the repository root, not a directory inside it'
    rescue Errno::ENOENT
      raise InvalidInput, 'Repository directory does not exist'
    end

    def revision(ref)
      raise InvalidInput, 'A non-option Git revision is required' if ref.to_s.empty? || ref.start_with?('-')

      git('rev-parse', '--verify', '--end-of-options', "#{ref}^{commit}").strip
    end

    def tree(revision)
      gaps = []
      skipped = []
      entries = git('ls-tree', '-r', '-l', '-z', '--full-tree', revision).split("\0")
      selected = entries.filter_map do |entry|
        header, path = entry.split("\t", 2)
        mode, type, oid, size = header.split
        validate_path!(path)
        if mode == '160000'
          gaps << "Submodule was not inspected: #{path}"
          next
        end
        unless permitted?(path)
          skipped << path
          next
        end
        unless type == 'blob' && BLOB_MODES.include?(mode)
          gaps << "Non-regular file was not inspected: #{path}"
          next
        end
        if size.to_i > 16_384
          gaps << "File exceeds 16 KiB: #{path}"
          next
        end

        [path, oid]
      end
      raise LimitExceeded, 'Repository exceeds 100 supported files per revision' if selected.size > 100

      Tree.new(files: blobs(selected), gaps: gaps, skipped: skipped)
    end

    def validate_path!(path)
      return if path&.valid_encoding? && !path.start_with?('/') && !path.match?(/[[:cntrl:]]/) &&
                !path.split('/').intersect?(['', '.', '..'])

      raise InvalidInput, 'Invalid Git tree path'
    end

    def permitted?(path)
      profile.fetch('file_patterns').any? { |pattern| File.fnmatch?(pattern, path, File::FNM_PATHNAME) }
    end

    # One process per revision. Sizes were already bounded from ls-tree, so the stream is at most
    # 100 blobs of 16 KiB plus headers.
    def blobs(selected)
      return {} if selected.empty?

      stream = git('cat-file', '--batch', stdin: "#{selected.map(&:last).join("\n")}\n").b
      cursor = 0
      bytes = 0
      selected.to_h do |path, oid|
        newline = stream.index("\n", cursor)
        raise InvalidInput, 'Unexpected local Git object stream' unless newline

        id, type, size = stream.byteslice(cursor, newline - cursor).split
        raise InvalidInput, "Local Git object is unavailable: #{path}" unless id == oid && type == 'blob'

        length = Integer(size, 10)
        body = stream.byteslice(newline + 1, length)
        raise InvalidInput, 'Unexpected local Git object stream' unless body && body.bytesize == length

        cursor = newline + 1 + length + 1
        body.force_encoding(Encoding::UTF_8)
        raise InvalidInput, "Source must be UTF-8 text: #{path}" unless body.valid_encoding? && !body.include?("\0")

        bytes += length
        raise LimitExceeded, 'Source bundle exceeds 1 MiB' if bytes > 1_048_576

        [path, body]
      end
    end

    def scrubbed_environment
      # Ignore inherited Git overrides and never fetch missing partial-clone objects.
      ENV.keys.grep(/\AGIT_/).to_h { |key| [key, nil] }.merge(
        'GIT_CONFIG_NOSYSTEM' => '1', 'GIT_CONFIG_GLOBAL' => File::NULL,
        'GIT_TERMINAL_PROMPT' => '0', 'GIT_NO_LAZY_FETCH' => '1'
      )
    end

    def git(*arguments, stdin: nil, limit: OUTPUT_LIMIT)
      output = +''.b
      errors = +''.b
      command = ['git', *GIT_OPTIONS, '-C', @repository, *arguments]
      Open3.popen3(@environment, *command, pgroup: true) do |input, out, err, process|
        deadline = monotonic + TIMEOUT_SECONDS
        input.write(stdin) if stdin
        input.close
        drain(out, output, err, errors, deadline: deadline, limit: limit)
        raise LimitExceeded, 'Local Git command timed out' unless process.join(remaining(deadline))
        raise InvalidInput, failure_message(arguments.first, errors) unless process.value.success?
      ensure
        kill(process) if process&.alive?
      end
      output.force_encoding(Encoding::UTF_8)
    rescue Errno::ENOENT
      raise InvalidInput, 'Git executable is unavailable'
    end

    # stdout and stderr are read together under one deadline so a chatty Git process cannot block on either pipe,
    # and diagnostics never mix into parsed data.
    def drain(out, output, err, errors, deadline:, limit:)
      open = [out, err]
      until open.empty?
        ready, = IO.select(open, nil, nil, remaining(deadline))
        raise LimitExceeded, 'Local Git command timed out' unless ready

        ready.each do |io|
          begin
            chunk = io.readpartial(16_384)
          rescue EOFError
            open.delete(io)
            next
          end
          if io.equal?(out)
            output << chunk
            raise LimitExceeded, 'Local Git output exceeds its byte limit' if output.bytesize > limit
          elsif errors.bytesize < STDERR_LIMIT
            errors << chunk
          end
        end
      end
    end

    def failure_message(subcommand, errors)
      detail = SlopGuard.printable(errors.force_encoding(Encoding::UTF_8).scrub.lines.first.to_s.strip)
      suffix = detail.empty? ? '' : " (#{detail})"
      "Local Git #{subcommand} failed#{suffix}; check repository, revisions and local history"
    end

    def remaining(deadline)
      [deadline - monotonic, 0.0].max
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def kill(process)
      Process.kill('KILL', -process.pid)
    rescue Errno::ESRCH, Errno::EPERM
      # Already gone, or the group leader has exited and left no killable members.
      nil
    end
  end
end
