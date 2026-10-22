require "json"
require "prism"
require "rbs"

class RubySdk
  # Reads a module's types where its author writes them, in `#:` comments:
  # RBS 4's inline syntax, which Steep checks. Comments leave no trace in a
  # loaded method, so generation reads them here and writes what they say to
  # sdk/entrypoint/signatures.json, which the module reads on every call.
  #
  # Each def and field is recorded with its line. A def that cannot be a
  # function is recorded with the reason, not refused: only the registry
  # knows which defs are functions.
  module Signatures
    # The diagnostics of the inline parser that are mistakes in annotations.
    MISTAKES = [RBS::InlineParser::Diagnostic::AnnotationSyntaxError,
                RBS::InlineParser::Diagnostic::UnusedInlineAnnotation].freeze

    class Refused < StandardError; end

    module_function

    # files: path to source. The result: path to the classes and modules the
    # file opens, each with its fields and annotated defs.
    def parse(files)
      files.sort.to_h { |path, source| [path, Source.new(path, source).scopes] }.reject { |_, scopes| scopes.empty? }
    end

    # sdk/entrypoint/signatures.json for a module's directory: what its lib/
    # declares, as generation writes it.
    def json(directory)
      files = directory.glob(pattern: "lib/**/*.rb").to_h { [it, directory.file(path: it).contents] }
      "#{JSON.pretty_generate(parse(files))}\n"
    end

    # A type the API can carry, as JSON: a constant's name as written, "bool",
    # "void", "self", { "optional" => type } or { "list" => type }.
    def type(rbs, result: false)
      case rbs
      when RBS::Types::Bases::Bool then "bool"
      when RBS::Types::Bases::Void, RBS::Types::Bases::Nil then result ? "void" : refuse("#{rbs} is a result type only")
      when RBS::Types::Bases::Self, RBS::Types::Bases::Instance then "self"
      when RBS::Types::Optional then { "optional" => type(rbs.type) }
      when RBS::Types::Union then union(rbs)
      when RBS::Types::ClassInstance then class_instance(rbs)
      when RBS::Types::Bases::Any then refuse("untyped is no type the API can carry; name the type")
      when RBS::Types::Alias then refuse("#{rbs} is a type alias; write the type it stands for")
      else refuse("#{rbs} is no type the API can carry")
      end
    end

    def union(rbs)
      types = rbs.types.grep_v(RBS::Types::Bases::Nil)
      refuse("#{rbs} is a union; only T | nil, or T?, is") unless types.size == 1 && rbs.types.size == 2

      { "optional" => type(types.first) }
    end

    def class_instance(rbs)
      return rbs.name.to_s if rbs.args.empty?
      return { "list" => type(rbs.args.first) } if %w[Array ::Array].include?(rbs.name.to_s) && rbs.args.size == 1

      refuse("#{rbs} is generic; a list is Array[T], and no other generic type is")
    end

    def refuse(message) = raise(Refused, message)

    # The JSON form of a keyword's default: a literal's value, a constant's
    # name, resolved once the module has loaded, or any other expression,
    # which only Ruby can evaluate.
    def default(node)
      value = literal(node)
      return { "value" => value.first } if value
      return { "constant" => node.slice } if node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)

      { "expression" => node.slice }
    end

    # [value], or nil for a node that is not a literal.
    def literal(node)
      case node
      when Prism::StringNode then [node.unescaped]
      when Prism::IntegerNode, Prism::FloatNode then [node.value]
      when Prism::TrueNode then [true]
      when Prism::FalseNode then [false]
      when Prism::NilNode then [nil]
      when Prism::ArrayNode
        values = node.elements.map { literal(it) }
        values.all? ? [values.map { it&.first }] : nil
      end
    end

    # One file: its classes and modules, by the inline parser of RBS 4.
    class Source
      def initialize(path, text)
        prism = Prism.parse(text)
        @result = RBS::InlineParser.parse(RBS::Buffer.new(name: Pathname(path), content: text), prism)
        @trailing = prism.comments.group_by { it.location.start_line }
        @mistakes = @result.diagnostics.select { |diagnostic| MISTAKES.any? { diagnostic.is_a?(it) } }
        @scopes = [] #: Array[json]
      end

      def scopes
        declarations(@result.declarations, [])
        @scopes
      end

      private

      def declarations(decls, nesting)
        decls.each do |decl|
          case decl
          when RBS::AST::Ruby::Declarations::ClassDecl then declaration(decl, decl.class_name, nesting)
          when RBS::AST::Ruby::Declarations::ModuleDecl then declaration(decl, decl.module_name, nesting)
          end
        end
      end

      def declaration(decl, written, nesting)
        name = written.absolute? || nesting.empty? ? written.to_s.delete_prefix("::") : "#{nesting.first}::#{written}"
        inner = [name, *nesting]
        records = { "fields" => fields(decl.node) }.merge(defs(decl)).reject { |_, value| value.empty? }
        @scopes << { "class" => name, "nesting" => inner, **records } unless records.empty?
        declarations(decl.members, inner)
      end

      def defs(decl)
        previous = decl.location.start_line
        records = { "methods" => {}, "singleton_methods" => {} } #: Hash[String, json]
        decl.members.each do |member|
          if member.is_a?(RBS::AST::Ruby::Members::DefMember)
            record = Def.new(member, mistakes_between(previous, member.location.start_line)).record
            records.fetch(member.singleton? ? "singleton_methods" : "methods")[member.name.to_s] = record if record
          end
          previous = member.location.end_line
        end
        records.reject { |_, value| value.empty? }
      end

      # What the parser found wrong in the comments before a def: an
      # annotation that does not parse, or one that belongs to no def, as
      # when `function` sits between a `#:` line and its def.
      def mistakes_between(first, last)
        @mistakes.select { (first...last).cover?(it.location.start_line) }.map do |mistake|
          hint = " (an annotation sits right above its def, below function and arg)" if
            mistake.is_a?(RBS::InlineParser::Diagnostic::UnusedInlineAnnotation)
          "line #{mistake.location.start_line}: #{mistake.message}#{hint}"
        end
      end

      def fields(node)
        body = node.body
        statements = body.is_a?(Prism::StatementsNode) ? body.body : [] #: Array[Prism::node]
        fields = {} #: json
        statements.each do |call|
          next unless call.is_a?(Prism::CallNode) && call.name == :field && call.receiver.nil?

          name = call.arguments&.arguments&.first
          fields[name.unescaped] = field(call) if name.is_a?(Prism::SymbolNode) || name.is_a?(Prism::StringNode)
        end
        fields
      end

      # A field's type is the `#:` comment that ends its line, which Steep
      # reads as an assertion on the call.
      def field(call)
        record = { "line" => call.location.start_line } #: json
        comment = (@trailing[call.location.end_line] || []).find do |trailing|
          trailing.location.start_offset >= call.location.end_offset && trailing.slice.start_with?("#:")
        end
        comment ? record.merge(field_type(comment.slice.delete_prefix("#:"))) : record
      end

      def field_type(text)
        type = RBS::Parser.parse_type(text, require_eof: true) or Signatures.refuse("#:#{text} names no type")
        { "type" => Signatures.type(type) }
      rescue RBS::ParsingError => e
        { "refused" => "#:#{text} does not parse: #{e.message.sub(/\A.*?: /, "")}" }
      rescue Refused => e
        { "refused" => e.message }
      end
    end

    # One def and its annotation, as a function would need them.
    class Def
      def initialize(member, mistakes)
        @member = member
        @mistakes = mistakes
        @keywords = member.node.parameters&.keywords || [] #: Array[Prism::node]
      end

      def record
        return nil if @member.method_type.empty? && @mistakes.empty?

        { "line" => @member.location.start_line }.merge(types)
      end

      private

      def types
        { "params" => params, "returns" => returns }
      rescue Refused => e
        { "refused" => e.message }
      end

      def method_type = @method_type ||= single_method_type

      def single_method_type
        Signatures.refuse(@mistakes.join("; ")) unless @mistakes.empty?
        overloads = @member.overloads
        Signatures.refuse("it has #{overloads.size} method types; a function has one") if overloads.size > 1
        method_type = overloads.fetch(0).method_type
        unless method_type.type_params.empty?
          Signatures.refuse("its method type has type parameters; a function's has none")
        end
        Signatures.refuse("it takes a block; a function takes keywords only") if method_type.block
        function = method_type.type
        return function if function.is_a?(RBS::Types::Function)

        Signatures.refuse("its parameters are (?); write each keyword with its type")
      end

      def params
        function = method_type
        check_keywords_only(function)
        check_agreement(function)
        check_no_descriptions
        keywords.map do |name, default|
          param = function.required_keywords[name] || function.optional_keywords.fetch(name)
          record = { "name" => name.to_s, "type" => typed(name.to_s) { Signatures.type(param.type) } }
          default ? record.merge("default" => Signatures.default(default)) : record
        end
      end

      # The def's keywords in order, each with its default's node, if any.
      def keywords
        @keywords.filter_map do |node|
          case node
          when Prism::RequiredKeywordParameterNode then [node.name, nil]
          when Prism::OptionalKeywordParameterNode then [node.name, node.value]
          end
        end
      end

      def returns = typed("the result") { Signatures.type(method_type.return_type, result: true) }

      def typed(what)
        yield
      rescue Refused => e
        raise Refused, "#{what}: #{e.message}"
      end

      def check_keywords_only(function)
        parameters = @member.node.parameters
        positional = function.required_positionals + function.optional_positionals + function.trailing_positionals +
                     [function.rest_positionals, function.rest_keywords].compact
        loose = parameters ? parameters.requireds + parameters.optionals + parameters.posts : [] #: Array[untyped]
        loose += [parameters.rest, parameters.keyword_rest, parameters.block].compact if parameters
        return if positional.empty? && loose.empty?

        Signatures.refuse("it takes positional, rest or block parameters; a function takes keywords only")
      end

      def check_agreement(function)
        annotated = function.required_keywords.keys.map { "#{it}:" } + function.optional_keywords.keys.map { "?#{it}:" }
        defined = keywords.map { |name, default| "#{"?" if default}#{name}:" }
        return if annotated.sort == defined.sort

        Signatures.refuse("its annotation takes (#{annotated.join(", ")}) but the def takes (#{defined.join(", ")})")
      end

      # Descriptions live in the declarations, arg :name, doc: "...".
      def check_no_descriptions
        annotations = @member.method_type.type_annotations
        return unless annotations.is_a?(RBS::AST::Ruby::Members::MethodTypeAnnotation::DocStyle)

        described = annotations.all_param_annotations.find do |annotation|
          annotation.is_a?(RBS::AST::Ruby::Annotations::ParamTypeAnnotation) && annotation.comment_location
        end
        return unless described.is_a?(RBS::AST::Ruby::Annotations::ParamTypeAnnotation)

        name = described.name_location.source
        Signatures.refuse("the description after -- is not read; describe #{name} with arg :#{name}, doc: \"...\"")
      end
    end
  end
end
