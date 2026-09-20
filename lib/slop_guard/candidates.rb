# frozen_string_literal: true

require 'prism'

module SlopGuard
  # Enumerates supported Ruby methods and tests without executing reviewed code.
  class Candidates
    attr_reader :items, :gaps

    EXAMPLES = %i[it specify example].freeze
    UNSUPPORTED = %i[eval class_eval module_eval define_method shared_examples shared_examples_for it_behaves_like
                     include_examples shared_context include_context].freeze
    KNOWN_REQUIRES = %w[rspec simplecov colorize ipaddr stringio open3 tempfile rbconfig json set benchmark].freeze

    def initialize(files)
      @items = []
      @gaps = []
      files.each do |path, text|
        next unless path.end_with?('.rb')

        result = Prism.parse(text)
        if result.failure?
          gaps << "Ruby parse error: #{path}"
          next
        end
        walk(result.value, path, files, [])
      end
      gaps << 'Ambiguous duplicate candidate identities' unless items.map { |item| item['id'] }.uniq.size == items.size
      gaps << 'Too many test candidates' if tests.size > 100
    end

    def tests
      items.select { |item| item['kind'] == 'test' }
    end

    private

    def walk(node, path, files, names)
      scope = names
      case node
      when Prism::ClassNode, Prism::ModuleNode
        scope = names + [node.constant_path.slice]
        add(node, path, 'class', scope.join('::')) if node.is_a?(Prism::ClassNode)
      when Prism::DefNode
        add(node, path, 'method', [names.join('::'), node.name.to_s].join('#'))
      when Prism::CallNode
        check_call(node, path, files)
        if path.start_with?('spec/') && EXAMPLES.include?(node.name) && node.block
          description = node.arguments&.arguments&.first
          if description.is_a?(Prism::StringNode)
            add(node, path, 'test', (names + [description.unescaped]).join(' / '))
          else
            gaps << "Dynamic test description: #{path}"
          end
        end
        if path.start_with?('spec/') && %i[describe context].include?(node.name)
          scope = names + [node.arguments&.slice.to_s]
        end
      end
      node.compact_child_nodes.each { |child| walk(child, path, files, scope) }
    end

    def check_call(node, path, files)
      gaps << "Unsupported Ruby construct #{node.name}: #{path}" if UNSUPPORTED.include?(node.name)
      if path.start_with?('spec/') && %i[each times map
                                         class_exec].include?(node.name) && node.block && contains_example?(node.block)
        gaps << "Potential dynamically generated examples: #{path}"
      end
      if path.start_with?('spec/') && node.receiver&.slice == 'File' && %i[open read binread readlines foreach
                                                                           new].include?(node.name)
        fixture = node.arguments&.arguments&.first
        if fixture.is_a?(Prism::StringNode)
          gaps << "Missing fixture: #{fixture.unescaped}" unless files.key?(fixture.unescaped)
        else
          gaps << "Unresolved test fixture path: #{path}"
        end
      end
      return unless %i[require require_relative].include?(node.name)

      arg = node.arguments&.arguments&.first
      unless arg.is_a?(Prism::StringNode)
        gaps << "Dynamic require: #{path}"
        return
      end
      if node.name == :require_relative
        target = Pathname.new(File.join(File.dirname(path), arg.unescaped)).cleanpath.to_s
        target += '.rb' unless target.end_with?('.rb')
        gaps << "Missing dependency: #{target}" unless files.key?(target)
      elsif !KNOWN_REQUIRES.include?(arg.unescaped)
        gaps << "Uninspected dependency: #{arg.unescaped}"
      end
    end

    def contains_example?(node)
      (node.is_a?(Prism::CallNode) && EXAMPLES.include?(node.name)) || node.compact_child_nodes.any? { |child| contains_example?(child) }
    end

    def add(node, path, kind, name)
      items << { 'id' => SlopGuard.digest([path, kind, name])[0, 16], 'path' => path,
                 'kind' => kind, 'name' => name,
                 'line' => node.location.start_line, 'end_line' => node.location.end_line }
    end
  end
end
