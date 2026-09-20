# frozen_string_literal: true

require 'optparse'

module SlopGuard
  # The `bin/review` command. Parses arguments, composes the engine and maps outcomes to documented exit codes.
  class CLI
    # 0 complete, 1 completed with incomplete evidence, 2 usage or invalid input, 3 provider/budget/operational.
    EXIT_COMPLETE = 0
    EXIT_INCOMPLETE = 1
    EXIT_INVALID = 2
    EXIT_OPERATIONAL = 3
    # Leaves room for one full question next to the state, which is what the client checks per request.
    QUESTION_HEADROOM = 2048

    USAGE = "Usage: bin/review CASE_ID [--profile demo] [--inspect | --live | --show-rules]\n       " \
            'bin/review --repo PATH --base REF [--head REF] --expectations FILE|- ' \
            "[--profile ruby] [--inspect | --live | --show-rules]\n       " \
            'bin/review --input FILE --expectations FILE|- [--profile NAME] [--inspect | --live]'

    def initialize(stdout: $stdout, stderr: $stderr, stdin: $stdin, env: ENV)
      @stdout = stdout
      @stderr = stderr
      @stdin = stdin
      @env = env
    end

    def run(argv)
      options = parse(argv.dup)
      profile = load_profile(options)
      rules = Rules.new(options.fetch(:rules, profile.rules_dir))
      return show_rules(profile, rules) if options[:show_rules]

      snapshot = build_snapshot(options, profile)
      return inspect(snapshot, rules) if options[:inspect]

      live(snapshot, rules, options)
    rescue InvalidInput, OptionParser::ParseError => e
      fail_with(e, EXIT_INVALID, options)
    rescue ProviderError, LimitExceeded => e
      fail_with(e, EXIT_OPERATIONAL, options)
    rescue SystemCallError, Psych::Exception => e
      fail_with(InvalidInput.new("Cannot read input or trusted configuration: #{e.class}"), EXIT_INVALID, options)
    end

    private

    def parse(argv)
      options = { inspect: false, live: false, json: false, show_rules: false }
      parser = OptionParser.new do |opts|
        opts.banner = USAGE
        opts.on('--inspect', 'Print evidence offline without contacting Jev') { options[:inspect] = true }
        opts.on('--live', 'Send the selected evidence to Jev for a paid review') { options[:live] = true }
        opts.on('--show-rules', 'Print the resolved profile and rule definitions offline') do
          options[:show_rules] = true
        end
        opts.on('--json', 'Print machine-readable output, including errors') { options[:json] = true }
        opts.on('--repo PATH', 'Read a local Git repository without checking out or running its code') do |v|
          options[:repo] = v
        end
        opts.on('--base REF', 'Compare from the merge base with this local revision') { |v| options[:base] = v }
        opts.on('--head REF', 'Committed revision to review (default HEAD; excludes working-tree changes)') do |v|
          options[:head] = v
        end
        opts.on('--input FILE', 'Review a saved before/files/pr_body JSON document directly') do |v|
          options[:input] = v
        end
        opts.on('--expectations FILE',
                'Markdown with Expected behavior and Failure cases sections; - reads stdin') do |v|
          options[:expectations] = v
        end
        opts.on('--profile NAME', 'Trusted profile: ruby (default with --repo) or demo (default for CASE_ID)') do |v|
          options[:profile] = v
        end
        opts.on('--rules-dir PATH', 'Explicit trusted directory with g1.yml through g4.yml') { |v| options[:rules] = v }
        opts.on('--output DIR', 'Directory for live reports and ledgers (default tmp/reviews)') do |v|
          options[:output] = v
        end
        opts.on('--env-file PATH', 'Load TYPESAFE_API_KEY from this ignored file when the environment lacks it') do |v|
          options[:env_file] = v
        end
      end
      parser.parse!(argv)
      options[:case] = argv.first
      modes = options.values_at(:inspect, :live, :show_rules).count(true)
      raise InvalidInput, parser.to_s unless modes == 1
      raise InvalidInput, parser.to_s unless valid_source?(options, argv)

      options
    end

    def valid_source?(options, argv)
      if options[:repo]
        argv.empty? && options[:base] && options[:expectations] && !options[:input]
      elsif options[:input]
        argv.empty? && options[:expectations] && !options[:base] && !options[:head]
      else
        (argv.size == 1 || options[:show_rules]) && argv.size <= 1 &&
          options.values_at(:base, :head, :expectations).all?(&:nil?)
      end
    end

    def load_profile(options)
      name = options[:profile] || (options[:repo] || options[:input] ? 'ruby' : 'demo')
      Profile.load(name)
    end

    def build_snapshot(options, profile)
      if options[:repo]
        source = GitSource.new(repository: options[:repo], base: options[:base], head: options[:head] || 'HEAD',
                               profile: profile)
        Snapshot.new(source.input(pr_body: expectations(options)), profile: profile)
      elsif options[:input]
        raw = File.binread(options[:input], (Limits::BUNDLE_BYTES * 2) + 1)
        raise InputTooLarge, 'Input document exceeds 2 MiB' if raw.bytesize > Limits::BUNDLE_BYTES * 2

        input = JSON.parse(raw)
        raise InvalidInput, 'Input document must be an object' unless input.is_a?(Hash)

        Snapshot.new(input.merge('pr_body' => expectations(options)), profile: profile)
      else
        require_relative 'eval'
        Snapshot.new(Dataset.new(File.join(ROOT, 'eval')).input(options.fetch(:case)), profile: profile)
      end
    rescue JSON::ParserError
      raise InvalidInput, 'Input document is not valid JSON'
    end

    def expectations(options)
      path = options.fetch(:expectations)
      raw = path == '-' ? @stdin.read(Limits::BODY_BYTES + 1).to_s : File.binread(path, Limits::BODY_BYTES + 1)
      raw.to_s.dup.force_encoding(Encoding::UTF_8)
    end

    def show_rules(profile, rules)
      @stdout.puts JSON.pretty_generate('profile' => profile.to_h, 'rules_revision' => rules.revision,
                                        'rules_files' => rules.files, 'definitions' => rules.definitions)
      EXIT_COMPLETE
    end

    def inspect(snapshot, rules)
      bytes = snapshot.state_bytes
      @stdout.puts JSON.pretty_generate('snapshot' => snapshot.identity, 'gaps' => snapshot.gaps,
                                        'expectation_gaps' => snapshot.expectations.gaps,
                                        'skipped_paths' => snapshot.skipped, 'source' => snapshot.source,
                                        'profile' => snapshot.profile.to_h, 'rules_revision' => rules.revision,
                                        'rules_files' => rules.files, 'state_bytes' => bytes,
                                        'live_limit_bytes' => JevClient::MAX_STATE_BYTES,
                                        'fits_live_limit' => bytes + QUESTION_HEADROOM <= JevClient::MAX_STATE_BYTES,
                                        'evidence' => snapshot.state)
      EXIT_COMPLETE
    end

    def live(snapshot, rules, options)
      api_key = credentials(options)
      directory = File.join(options[:output] || @env.fetch('SLOP_GUARD_OUTPUT_DIR', File.join(ROOT, 'tmp/reviews')),
                            "#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}-#{Process.pid}")
      ledger = File.join(directory, 'requests.jsonl')
      budget = Budget.new(ledger: ledger)
      client = JevClient.new(api_key: api_key, budget: budget)
      report = Evaluator.new(client: client, rules: rules).call(snapshot)
      report_path = File.join(directory, 'report.json')
      File.write(report_path, JSON.pretty_generate(report))
      @stderr.puts "Report saved to #{report_path}"
      if options[:json]
        @stdout.puts JSON.pretty_generate(report.merge('report_path' => report_path, 'ledger_path' => ledger))
      else
        @stdout.puts Report.markdown(report)
      end
      { 'complete' => EXIT_COMPLETE, 'incomplete' => EXIT_INCOMPLETE }.fetch(report['status'], EXIT_OPERATIONAL)
    end

    # Credentials come from the environment; a file is read only when explicitly named. Environment wins.
    def credentials(options)
      env = @env.to_h
      env_file = options[:env_file] || env.fetch('SLOP_GUARD_ENV_FILE', nil)
      if env_file
        raise InvalidInput, "Credential file does not exist: #{env_file}" unless File.file?(env_file)

        require 'dotenv'
        env = Dotenv.parse(env_file).merge(env)
      end
      api_key = env.fetch('TYPESAFE_API_KEY', '')
      raise ProviderError, 'TYPESAFE_API_KEY is not configured' if api_key.strip.empty?

      api_key
    end

    def fail_with(error, status, options)
      message = SlopGuard.printable(error.message, keep_newlines: true)
      if options&.fetch(:json, false)
        @stdout.puts JSON.generate('error' => { 'class' => error.class.name.delete_prefix('SlopGuard::'),
                                                'message' => message, 'exit_status' => status })
      else
        @stderr.puts message
      end
      status
    end
  end
end
