require_relative "../test_helper"
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ruby_sdk/signatures"

class SignaturesTest < Minitest::Test
  Signatures = RubySdk::Signatures

  def parse(source, path: "lib/main.rb") = Signatures.parse(path => source).fetch(path, [])

  def scope(source, name = "Main") = parse(source).find { it["class"] == name }

  def method_record(source, name, singleton: false)
    scope(source).fetch(singleton ? "singleton_methods" : "methods").fetch(name)
  end

  # The type of a function's one keyword, x.
  def param_type(rbs) = method_record("class Main\n  #: (x: #{rbs}) -> void\n  def a(x:) = nil\nend\n", "a")

  def result_type(rbs) = method_record("class Main\n  #: () -> #{rbs}\n  def a = nil\nend\n", "a")

  def test_a_module_reads_as_its_classes_fields_and_annotated_defs
    source = <<~RUBY
      require "dagger"

      class Main
        extend Dagger::Mod::Object

        field :greeting, default: "hi" #: String
        field :count, doc: "How many",
                      private: true #: Integer?

        function "Greet."
        arg :name, doc: "Who."
        #: (name: String, ?mood: Mood) -> String
        def greet(name:, mood: Mood::HAPPY) = "\#{greeting} \#{name} \#{mood}"

        constructor
        #: (?count: Integer) -> instance
        def self.create(count: 1) = new(count:)

        def helper(value) = value
      end
    RUBY

    assert_equal(
      { "lib/main.rb" => [{
        "class" => "Main", "nesting" => ["Main"],
        "fields" => { "greeting" => { "line" => 6, "type" => "String" },
                      "count" => { "line" => 7, "type" => { "optional" => "Integer" } } },
        "methods" => { "greet" => {
          "line" => 13, "returns" => "String",
          "params" => [{ "name" => "name", "type" => "String" },
                       { "name" => "mood", "type" => "Mood", "default" => { "constant" => "Mood::HAPPY" } }]
        } },
        "singleton_methods" => { "create" => {
          "line" => 17, "returns" => "self",
          "params" => [{ "name" => "count", "type" => "Integer", "default" => { "value" => 1 } }]
        } }
      }] },
      Signatures.parse("lib/main.rb" => source, "lib/empty.rb" => "require \"json\"\n")
    )
  end

  def test_nested_classes_keep_their_lexical_scopes
    source = "module Types\n  class Greeter\n    field :x #: Mood\n  end\nend\n" \
             "class Types::Other\n  field :y #: Mood\nend\n"
    scopes = parse(source).map { [it["class"], it["nesting"]] }

    assert_equal [["Types::Greeter", %w[Types::Greeter Types]], ["Types::Other", ["Types::Other"]]], scopes
  end

  TYPES = {
    "String" => "String",
    "::Dagger::Clients::Core::Directory" => "::Dagger::Clients::Core::Directory",
    "Core::Directory" => "Core::Directory",
    "bool" => "bool",
    "String?" => { "optional" => "String" },
    "String | nil" => { "optional" => "String" },
    "nil | Integer" => { "optional" => "Integer" },
    "Array[String]" => { "list" => "String" },
    "::Array[Integer]" => { "list" => "Integer" },
    "Array[Array[Integer]]" => { "list" => { "list" => "Integer" } },
    "Array[Mood?]?" => { "optional" => { "list" => { "optional" => "Mood" } } }
  }.freeze

  def test_the_types_an_argument_can_have
    TYPES.each do |rbs, json|
      assert_equal [{ "name" => "x", "type" => json }], param_type(rbs)["params"], rbs
    end
  end

  def test_the_types_only_a_result_can_have
    { "void" => "void", "nil" => "void", "self" => "self", "instance" => "self", "String" => "String" }
      .each { |rbs, json| assert_equal json, result_type(rbs)["returns"], rbs }
  end

  REFUSED_TYPES = {
    "untyped" => "x: untyped is no type the API can carry; name the type",
    "String | Integer" => "x: String | Integer is a union; only T | nil, or T?, is",
    "boolish" => "x: boolish is a type alias; write the type it stands for",
    "[String, Integer]" => "x: [ String, Integer ] is no type the API can carry",
    "{ a: String }" => "x: { a: String } is no type the API can carry",
    "Hash[String, Integer]" => "x: Hash[String, Integer] is generic; a list is Array[T], and no other generic type is",
    "Array[String, Integer]" =>
      "x: Array[String, Integer] is generic; a list is Array[T], and no other generic type is",
    "_Each[String]" => "x: _Each[String] is no type the API can carry",
    "\"a\"" => "x: \"a\" is no type the API can carry",
    "singleton(String)" => "x: singleton(String) is no type the API can carry",
    "^() -> String" => "x: ^() -> String is no type the API can carry",
    "void" => "line 2: Syntax error: void type is not allowed here",
    "nil" => "x: nil is a result type only"
  }.freeze

  def test_types_the_api_cannot_carry_are_refused_with_the_reason
    REFUSED_TYPES.each do |rbs, reason|
      assert_equal reason, param_type(rbs)["refused"], rbs
    end
  end

  def test_defaults_are_literals_constants_or_expressions
    record = method_record(<<~RUBY, "a")
      class Main
        #: (?s: String, ?i: Integer, ?f: Float, ?t: bool, ?n: String?, ?l: Array[String], ?m: Mood, ?e: String) -> void
        def a(s: "x\\ty", i: -2, f: 0.5, t: false, n: nil, l: %w[a b], m: Types::Mood::HAPPY, e: ENV.fetch("E")) = nil
      end
    RUBY

    defaults = record["params"].map { it["default"] }

    assert_equal [{ "value" => "x\ty" }, { "value" => -2 }, { "value" => 0.5 }, { "value" => false },
                  { "value" => nil }, { "value" => %w[a b] }, { "constant" => "Types::Mood::HAPPY" },
                  { "expression" => 'ENV.fetch("E")' }], defaults
  end

  def test_a_def_without_an_annotation_is_not_recorded
    source = "class Main\n  field :x #: String\n  def plain(a) = a\nend\n"

    refute scope(source).key?("methods")
  end

  def test_the_doc_style_annotation_reads_as_the_method_type
    record = method_record(<<~RUBY, "a")
      class Main
        # @rbs name: String
        # @rbs return: Array[String]
        def a(name:) = [name]
      end
    RUBY

    assert_equal [[{ "name" => "name", "type" => "String" }], { "list" => "String" }],
                 [record["params"], record["returns"]]
  end

  REFUSED_DEFS = {
    "an annotation without the def's keywords" =>
      ["#: (name: String) -> String\ndef a(nam:) = nam",
       "its annotation takes (name:) but the def takes (nam:)"],
    "an optional keyword the def requires" =>
      ["#: (?name: String) -> String\ndef a(name:) = name",
       "its annotation takes (?name:) but the def takes (name:)"],
    "a positional parameter" =>
      ["#: (String) -> String\ndef a(name) = name",
       "it takes positional, rest or block parameters; a function takes keywords only"],
    "a rest of keywords" =>
      ["#: (**String) -> String\ndef a(**rest) = rest.to_s",
       "it takes positional, rest or block parameters; a function takes keywords only"],
    "a block" => ["#: () { () -> void } -> String\ndef a(&) = \"\"",
                  "it takes a block; a function takes keywords only"],
    "overloads" => ["#: () -> String\n#: (name: String) -> String\ndef a(name: \"\") = name",
                    "it has 2 method types; a function has one"],
    "type parameters" => ["#: [T] (x: T) -> T\ndef a(x:) = x",
                          "its method type has type parameters; a function's has none"],
    "a keyword without a type in the doc style" =>
      ["# @rbs return: String\ndef a(name:) = name", "name: untyped is no type the API can carry; name the type"],
    "a description in the annotation" =>
      ["# @rbs name: String -- Who.\n# @rbs return: String\ndef a(name:) = name",
       "the description after -- is not read; describe name with arg :name, doc: \"...\""],
    "an annotation that does not parse" =>
      ["#: (name: String -> String\ndef a(name:) = name",
       "line 2: Syntax error: unexpected token for function parameter name"],
    "an annotation above function, which belongs to no def" =>
      ["#: () -> String\nfunction \"A.\"\ndef a = \"\"",
       "line 2: Unused inline rbs annotation (an annotation sits right above its def, below function and arg)"]
  }.freeze

  def test_a_def_that_cannot_be_a_function_is_recorded_with_the_reason
    REFUSED_DEFS.each do |what, (body, reason)|
      record = method_record("class Main\n#{body}\nend\n", "a")

      assert_equal reason, record["refused"], what
      assert_equal body.lines.size + 1, record["line"], what
    end
  end

  def test_a_mistake_before_another_def_is_not_this_ones
    source = "class Main\n  #:nodoc:\n  def helper = nil\n\n  #: () -> String\n  def a = \"\"\nend\n"

    assert_equal({ "line" => 6, "params" => [], "returns" => "String" }, method_record(source, "a"))
    assert_match(/Syntax error/, method_record(source, "helper")["refused"])
  end

  def test_a_field_takes_the_annotation_that_ends_its_line
    fields = scope(<<~RUBY)["fields"]
      class Main
        field :plain
        field :typed, default: "x" #: String
        field :broken #: Array[
        field :loose #: Hash[String, Integer]
        field :later # a comment, then #: String
        other :ignored #: String
      end
    RUBY

    broken = "#: Array[ does not parse: Syntax error: unexpected token for simple type, token=`` (pEOF)"
    loose = "Hash[String, Integer] is generic; a list is Array[T], and no other generic type is"

    assert_equal({ "plain" => { "line" => 2 }, "typed" => { "line" => 3, "type" => "String" },
                   "broken" => { "line" => 4, "refused" => broken }, "loose" => { "line" => 5, "refused" => loose },
                   "later" => { "line" => 6 } }, fields)
  end
end
