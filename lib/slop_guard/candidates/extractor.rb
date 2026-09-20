# frozen_string_literal: true

require 'prism'

module SlopGuard
  class Candidates
    # One pass over every Ruby file with Prism: collects candidates, require_relative dependencies and the gaps
    # that make evidence incomplete. Used once per snapshot and discarded.
    class Extractor
      EXAMPLES = %i[it specify example].freeze
      GROUPS = %i[describe context].freeze
      UNSUPPORTED = %i[eval class_eval module_eval define_method shared_examples shared_examples_for it_behaves_like
                       include_examples shared_context include_context].freeze
      DYNAMIC_EXAMPLE_ITERATORS = %i[each times map class_exec].freeze
      FILE_READS = %i[open read binread readlines foreach new].freeze

      def initialize(files, profile:)
        @files = files
        @profile = profile
        @items = []
        @gaps = []
        @dependencies = Hash.new { |hash, key| hash[key] = [] }
      end

      def call
        files.each do |path, text|
          next unless path.end_with?('.rb')

          result = Prism.parse(text)
          if result.failure?
            gaps << "Ruby parse error: #{path}"
            next
          end
          walk(result.value, path, [])
        end
        ids = items.map { |item| item['id'] }
        gaps << 'Ambiguous duplicate candidate identities' unless ids.uniq.size == ids.size
        gaps << 'Too many test candidates' if items.count { |item| item['kind'] == 'test' } > Limits::TEST_CANDIDATES
        Candidates.new(items: items, gaps: gaps, dependencies: dependencies)
      end

      private

      attr_reader :files, :profile, :items, :gaps, :dependencies

      def walk(node, path, names)
        scope = names
        case node
        when Prism::ClassNode, Prism::ModuleNode
          scope = names + [node.constant_path.slice]
          add(node, path, 'class', scope.join('::')) if node.is_a?(Prism::ClassNode)
        when Prism::DefNode
          add(node, path, 'method', [names.join('::'), node.name.to_s].join('#'))
        when Prism::CallNode
          check_call(node, path)
          if test?(path) && EXAMPLES.include?(node.name) && node.block
            add_example(node, path, names)
          elsif test?(path) && GROUPS.include?(node.name)
            scope = names + [node.arguments&.slice.to_s]
          end
        end
        node.compact_child_nodes.each { |child| walk(child, path, scope) }
      end

      def add_example(node, path, names)
        description = first_argument(node)
        if description.is_a?(Prism::StringNode)
          add(node, path, 'test', (names + [description.unescaped]).join(' / '))
        else
          gaps << "Dynamic test description: #{path}"
        end
      end

      def check_call(node, path)
        gaps << "Unsupported Ruby construct #{node.name}: #{path}" if UNSUPPORTED.include?(node.name)
        check_dynamic_examples(node, path)
        check_fixture(node, path)
        check_require(node, path)
      end

      def check_dynamic_examples(node, path)
        return unless test?(path) && DYNAMIC_EXAMPLE_ITERATORS.include?(node.name) && node.block

        gaps << "Potential dynamically generated examples: #{path}" if contains_example?(node.block)
      end

      def check_fixture(node, path)
        return unless test?(path) && node.receiver&.slice == 'File' && FILE_READS.include?(node.name)

        fixture = first_argument(node)
        if fixture.is_a?(Prism::StringNode)
          gaps << "Missing fixture: #{fixture.unescaped}" unless files.key?(fixture.unescaped)
        else
          gaps << "Unresolved test fixture path: #{path}"
        end
      end

      def check_require(node, path)
        return unless %i[require require_relative].include?(node.name)

        arg = first_argument(node)
        unless arg.is_a?(Prism::StringNode)
          gaps << "Dynamic require: #{path}"
          return
        end
        if node.name == :require_relative
          target = Pathname.new(File.join(File.dirname(path), arg.unescaped)).cleanpath.to_s
          target += '.rb' unless target.end_with?('.rb')
          dependencies[path] << target
          gaps << "Missing dependency: #{target}" unless files.key?(target)
        elsif !profile.known_requires.include?(arg.unescaped)
          gaps << "Uninspected dependency: #{arg.unescaped}"
        end
      end

      def contains_example?(node)
        (node.is_a?(Prism::CallNode) && EXAMPLES.include?(node.name)) ||
          node.compact_child_nodes.any? { |child| contains_example?(child) }
      end

      def test?(path)
        profile.test_path?(path)
      end

      def first_argument(node)
        node.arguments&.arguments&.first
      end

      def add(node, path, kind, name)
        items << { 'id' => SlopGuard.digest([path, kind, name])[0, 16], 'path' => path,
                   'kind' => kind, 'name' => name,
                   'line' => node.location.start_line, 'end_line' => node.location.end_line }
      end
    end
  end
end
