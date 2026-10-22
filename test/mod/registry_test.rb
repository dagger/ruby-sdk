require_relative "mod_helper"

class RegistryTest < Minitest::Test
  include ModHelper

  MODULE = <<~RUBY.freeze
    class Color < Dagger::Mod::Enum
      description "A color."
      member :RED, "red", doc: "The red one."
      member :BLUE, "blue"
    end

    class Helper
      extend Dagger::Mod::Object

      field :level, doc: "A color." #: Color
    end

    class Main
      extend Dagger::Mod::Object

      description "The main object."
      field :greeting, default: "hello" #: String
      field :count, default: 1, doc: "How many" #: Integer

      function "A container."
      #: (?from: String) -> ModHelper::Core::Container
      def container(from: "alpine") = from

      function check: true
      #: () -> void
      def lint = nil

      function
      #: (?who: String?) -> Array[Main]
      def mob(who: nil) = who
    end
  RUBY

  def test_objects_and_their_fields
    declare(MODULE)
    description = describe

    assert_equal "Main", description.main_object
    assert_equal "The main object.", description.description
    assert_equal %w[Helper Main], description.objects.map(&:name)
    assert_equal %w[greeting count], object(description, "Main").fields.map(&:name)
    assert_equal({ kind: "ENUM_KIND", name: "Color", optional: false, elem: nil },
                 object(description, "Helper").fields.first.type.to_h)
  end

  def test_the_main_object_takes_its_fields_without_a_constructor
    declare(MODULE)
    constructor = object(describe, "Main").constructor

    assert_equal [nil, "How many"], constructor.args.map(&:description)
    assert_equal ['"hello"', "1"], constructor.args.map(&:default_value)
    assert_nil object(describe, "Helper").constructor
  end

  def test_functions_and_their_types
    declare(MODULE)
    description = describe
    mob = function(description, "Main", "mob")

    assert_equal({ kind: "OBJECT_KIND", name: "Container", optional: false, elem: nil },
                 function(description, "Main", "container").returns.to_h)
    assert function(description, "Main", "lint").check
    assert_equal "VOID_KIND", function(description, "Main", "lint").returns.kind
    assert_equal "LIST_KIND", mob.returns.kind
    assert_equal "Main", mob.returns.elem.name
    assert_equal [true, "null"], [mob.args.first.type.optional, mob.args.first.default_value]
  end

  def test_defaults_come_from_the_def
    declare(<<~RUBY)
      class Color < Dagger::Mod::Enum
        member :BLUE
      end

      class Main
        extend Dagger::Mod::Object

        STAMP = "stamp"

        function
        #: (?name: String, ?color: Color, ?stamp: String, ?at: Integer, ?tags: Array[String]) -> void
        def a(name: "x", color: Color::BLUE, stamp: STAMP, at: Time.now.to_i, tags: %w[a b]) = nil
      end
    RUBY
    args = function(describe, "Main", "a").args

    assert_equal ['"x"', '"BLUE"', '"stamp"', nil, '["a","b"]'], args.map(&:default_value)
    assert_equal([false, false, false, true, false], args.map { it.type.optional })
  end

  def test_enum_members
    declare(MODULE)
    members = describe.enums.first.values

    assert_equal(%w[RED BLUE], members.map(&:name))
    assert_equal(%w[red blue], members.map(&:value))
    assert_equal ["The red one.", nil], members.map(&:description)
  end

  def test_a_declared_constructor_is_the_main_object_constructor
    declare(<<~RUBY)
      class Main
        extend Dagger::Mod::Object

        field :source, private: true #: ModHelper::Core::Directory

        constructor "Build it."
        arg :name, name: "label", doc: "Where."
        #: (ws: ModHelper::Core::Workspace, ?name: String) -> instance
        def self.create(ws:, name: "x") = new(source: ws.directory(path: name))
      end
    RUBY
    main = object(describe, "Main")

    assert_equal ["", "Build it."], [main.constructor.name, main.constructor.description]
    assert_equal %w[ws label], main.constructor.args.map(&:name)
    assert_equal [nil, "Where."], main.constructor.args.map(&:description)
    assert_empty main.fields
  end

  def test_ignore_reaches_the_constructor_argument_of_a_field
    declare(<<~RUBY)
      class Main
        extend Dagger::Mod::Object

        field :source, private: true, ignore: ["vendor"] #: ModHelper::Core::Directory
      end
    RUBY
    arg = object(describe, "Main").constructor.args.first

    assert_equal [["vendor"], "Directory"], [arg.ignore, arg.type.name]
  end

  def test_state_is_set_from_field_keywords
    declare(<<~RUBY)
      class Main
        extend Dagger::Mod::Object

        field :a, default: "x" #: String
        field :b #: Integer
      end
    RUBY
    main = Fixtures::Main.new(b: 2)

    assert_equal ["x", 2], [main.a, main.b]
    assert_raises(ArgumentError) { Fixtures::Main.new(c: 1) }
  end

  def refusal(body)
    declare("class Main\n  extend Dagger::Mod::Object\n\n#{body}\nend\n")
    assert_raises(Dagger::Mod::RegistrationError) { describe }.message
  end

  def test_a_function_without_an_annotation_is_refused_at_its_def
    assert_equal "lib/main.rb:5: Main.a has no annotation that generation read; write its type on the line above " \
                 "the def, as #: (name: String) -> String", refusal("  function\n  def a = nil")
  end

  def test_an_annotation_that_does_not_parse_is_refused_with_its_line
    assert_equal "lib/main.rb:6: Main.a: line 5: Syntax error: unexpected token for function parameter name",
                 refusal("  function\n  #: (x: Integer -> void\n  def a(x:) = x")
  end

  def test_an_annotation_that_disagrees_with_its_def_is_refused_with_its_line
    assert_equal "lib/main.rb:6: Main.a: its annotation takes (name:) but the def takes (nam:)",
                 refusal("  function\n  #: (name: String) -> String\n  def a(nam:) = nam")
  end

  def test_a_function_above_its_annotation_leaves_the_def_without_one
    assert_equal "lib/main.rb:6: Main.a: line 4: Unused inline rbs annotation (an annotation sits right above its " \
                 "def, below function and arg)", refusal("  #: () -> String\n  function\n  def a = \"\"")
  end

  def test_a_def_edited_since_generation_asks_for_dagger_generate
    declare("class Main\n  extend Dagger::Mod::Object\n\n  function\n  #: (name: String) -> String\n  " \
            "def a(name:) = name\nend\n")
    Fixtures::Main.class_eval { def a(name:, extra:) = name + extra }
    error = assert_raises(Dagger::Mod::RegistrationError) { annotate }

    assert_equal "lib/main.rb:6: Main.a: the method takes (name:, extra:) but its annotation took (name:) when " \
                 "generation read it", error.message
  end

  def test_a_field_without_a_type_is_refused_with_its_line
    assert_equal "lib/main.rb:4: Main.x: the field has no type; end its line with one, as field :x #: String",
                 refusal("  field :x, doc: \"X.\"")
  end

  def test_a_type_that_names_no_constant_is_refused_with_its_line
    assert_equal "lib/main.rb:6: Main.a result: uninitialized constant ModHelper::Fixtures::Main::Nope",
                 refusal("  function\n  #: () -> Nope\n  def a = nil")
  end

  REFUSED = {
    "a cache policy" => "function cache: \"never\"\n#: () -> void\ndef a = nil",
    "a positional parameter" => "function\n#: (Integer) -> Integer\ndef a(x) = x",
    "an arg the method lacks" => "function\narg :x, doc: \"X.\"\n#: () -> void\ndef a = nil",
    "a predicate without name:" => "function\n#: () -> bool\ndef a? = true",
    "untyped" => "function\n#: () -> untyped\ndef a = nil",
    "a union" => "function\n#: (x: String | Integer) -> void\ndef a(x:) = nil",
    "a Hash" => "function\n#: () -> Hash[String, String]\ndef a = nil",
    "a Symbol" => "function\n#: () -> Symbol\ndef a = nil",
    "Object" => "function\n#: () -> Object\ndef a = nil",
    "an unregistered class" => "class Plain; end\nfunction\n#: () -> Plain\ndef a = nil",
    "a declaration without a def" => "function \"orphan\"",
    "a field whose type does not parse" => "field :x #: Array[",
    "a constructor on another object" =>
      "end\nclass Other\nextend Dagger::Mod::Object\nconstructor\n#: () -> instance\ndef self.create = new"
  }.freeze

  def test_refusals_at_generation
    REFUSED.each do |what, body|
      setup
      declare("class Main\nextend Dagger::Mod::Object\n#{body}\nend")

      assert_raises(Dagger::Mod::RegistrationError, what) { describe }
    end
  end

  REFUSED_AT_DECLARATION = {
    "an arg before any function" => "arg :x",
    "a field between a declaration and its def" => "function\nfield :x #: String",
    "a constructor that is not self.create" => "constructor\ndef self.build = new",
    "a function on a class method" => "function\ndef self.helper = nil",
    "a constructor on an instance method" => "constructor\ndef create = nil",
    "a field marked keys: and delta:" => "field :x, keys: true, delta: true #: Array[String]"
  }.freeze

  def test_refusals_at_declaration
    REFUSED_AT_DECLARATION.each do |what, body|
      setup

      assert_raises(Dagger::Mod::RegistrationError, what) do
        declare("class Main\nextend Dagger::Mod::Object\n#{body}\nend")
      end
    end
  end

  ITEMS = <<~RUBY.freeze
    class Item
      extend Dagger::Mod::Object

      field :name #: String
    end

    class Main
      extend Dagger::Mod::Object

      function
      #: () -> Items
      def items = Items.new(keys: [])
    end
  RUBY
  KEYS = "field :keys #: Array[String]".freeze
  GET = "function\n#: (key: String) -> Item\ndef get(key:) = Item.new(name: key)".freeze

  def collection(body)
    declare("#{ITEMS}\nclass Items\n  extend Dagger::Mod::Object\n  collection\n\n#{body}\nend\n")
    object(describe, "Items")
  end

  def line_of(text) = @sources.fetch("lib/main.rb").lines.index { it.include?(text) } + 1

  def test_a_collection_by_the_engines_member_names_needs_no_marker
    items = collection("#{KEYS}\nfield :delta #: ModHelper::Core::CollectionDelta?\n#{GET}")

    assert_equal Dagger::Mod::Description::Collection.new(keys: nil, get: nil, delta: nil), items.collection
    assert_equal [".withCollection"], Dagger::Mod::Entrypoint.collection(items.collection)
    assert_nil object(describe, "Item").collection
  end

  def test_a_collection_names_its_other_members_by_markers
    items = collection(<<~BODY)
      field :names, keys: true #: Array[String]
      field :changes, delta: true #: ModHelper::Core::CollectionDelta
      field :keys #: String

      function get: true
      #: (name: String) -> Item
      def lookup(name:) = Item.new(name:)
    BODY
    rendered = Dagger::Mod::Entrypoint.render_types(describe)

    assert_equal Dagger::Mod::Description::Collection.new(keys: "names", get: "lookup", delta: "changes"),
                 items.collection
    lines = ['typeDef.withObject("Items")', ".withCollection", '.withCollectionKeys("names")',
             '.withCollectionGet("lookup")', '.withCollectionDelta("changes")']
    assert_includes rendered, lines.join("\n        ")
  end

  # Each refusal names the member, or the collection line for a missing one.
  COLLECTION_REFUSALS = [
    [KEYS, "  collection", "the collection Items has no get function; declare def get(key:) returning an object, " \
                           "or mark one get: true"],
    [GET, "  collection", "the collection Items has no keys field; declare field :keys #: Array[String], or mark " \
                          "one keys: true"],
    ["field :names, keys: true #: Array[String]\nfield :ids, keys: true #: Array[String]\n#{GET}", "  collection",
     "Items marks names and ids keys:; a collection has one"],
    ["field :keys #: String\n#{GET}", "field :keys", "Items.keys: a collection's keys are a list of strings, " \
                                                     "numbers, booleans, scalars or enum members, none of them nil, " \
                                                     "as #: Array[String]"],
    ["field :keys #: Array[String?]\n#{GET}", "field :keys", "Items.keys: a collection's keys are a list of " \
                                                             "strings, numbers, booleans, scalars or enum members, " \
                                                             "none of them nil, as #: Array[String]"],
    ["field :keys, private: true #: Array[String]\n#{GET}", "field :keys",
     "Items.keys: a collection's keys field is not private: the engine reads it"],
    ["#{KEYS}\nfunction\n#: (key: Integer) -> Item\ndef get(key:) = Item.new(name: key.to_s)", "def get",
     "Items.get: a collection's get function takes one required argument of the key type, as #: (key: String) " \
     "-> Item"],
    ["#{KEYS}\nfunction\n#: (?key: String) -> Item\ndef get(key: \"a\") = Item.new(name: key)", "def get",
     "Items.get: a collection's get function takes one required argument of the key type, as #: (key: String) " \
     "-> Item"],
    ["#{KEYS}\nfunction\n#: (key: String) -> Item?\ndef get(key:) = nil", "def get",
     "Items.get: a collection's get function returns an object, never nil"],
    ["#{KEYS}\nfunction\n#: (key: String) -> String\ndef get(key:) = key", "def get",
     "Items.get: a collection's get function returns an object, never nil"],
    ["#{KEYS}\n#{GET}\nfield :delta #: String", "field :delta",
     "Items.delta: a collection's delta field is not private, and its type is " \
     "Dagger::Clients::Core::CollectionDelta"]
  ].freeze

  def test_a_collection_that_breaks_an_engine_rule_is_refused_at_the_member
    COLLECTION_REFUSALS.each do |body, at, message|
      setup
      error = assert_raises(Dagger::Mod::RegistrationError, message) { collection(body) }

      assert_equal "lib/main.rb:#{line_of(at)}: #{message}", error.message
    end
  end

  def test_a_marker_outside_a_collection_is_refused
    declare("#{ITEMS}\nclass Items\n  extend Dagger::Mod::Object\n\n  field :names, keys: true #: Array[String]\nend\n")
    error = assert_raises(Dagger::Mod::RegistrationError) { describe }

    assert_equal "lib/main.rb:#{line_of("field :names")}: Items.names is marked keys:, but Items is not a " \
                 "collection; add collection to the class", error.message
  end

  def test_an_interface_has_no_get_marker
    declare("class Main\n  extend Dagger::Mod::Object\nend\n\nmodule Shape\n  extend Dagger::Mod::Interface\n\n  " \
            "function get: true\n  #: (key: String) -> String\n  def get(key:) = key\nend\n")
    error = assert_raises(Dagger::Mod::RegistrationError) { describe }

    assert_equal "lib/main.rb:#{line_of("def get")}: Shape.get is marked get:, which marks a collection's get " \
                 "function; an interface is no collection", error.message
  end

  def test_enum_members_are_upper_snake_case
    assert_raises(Dagger::Mod::RegistrationError) { declare("class Color < Dagger::Mod::Enum\nmember :Red\nend") }
  end

  def test_the_main_object_must_be_registered
    error = assert_raises(Dagger::Mod::RegistrationError) { describe("Missing") }

    assert_match(/class Missing/, error.message)
  end
end
