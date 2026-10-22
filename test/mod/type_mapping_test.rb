require_relative "mod_helper"

# The README's type mapping, row by row: the type an annotation names, read at
# generation, resolved once the module has loaded, rendered as a TypeDef.
class TypeMappingTest < Minitest::Test
  include ModHelper

  ROWS = {
    "String" => { kind: "STRING_KIND" },
    "Integer" => { kind: "INTEGER_KIND" },
    "Float" => { kind: "FLOAT_KIND" },
    "bool" => { kind: "BOOLEAN_KIND" },
    "void" => { kind: "VOID_KIND", optional: true },
    "nil" => { kind: "VOID_KIND", optional: true },
    "String?" => { kind: "STRING_KIND", optional: true },
    "(Integer | nil)" => { kind: "INTEGER_KIND", optional: true },
    "Array[String]" => { kind: "LIST_KIND", elem: { kind: "STRING_KIND" } },
    "Array[Array[Integer]]" => { kind: "LIST_KIND", elem: { kind: "LIST_KIND", elem: { kind: "INTEGER_KIND" } } },
    "Array[Mood?]?" => { kind: "LIST_KIND", optional: true, elem: { kind: "ENUM_KIND", name: "Mood", optional: true } },
    "Main" => { kind: "OBJECT_KIND", name: "Main" },
    "self" => { kind: "OBJECT_KIND", name: "Main" },
    "Shape" => { kind: "INTERFACE_KIND", name: "Shape" },
    "Mood" => { kind: "ENUM_KIND", name: "Mood" },
    "Core::Directory" => { kind: "OBJECT_KIND", name: "Directory" },
    "::ModHelper::Core::Directory" => { kind: "OBJECT_KIND", name: "Directory" },
    "Core::JSON" => { kind: "SCALAR_KIND", name: "JSON" },
    "Core::NetworkProtocol" => { kind: "ENUM_KIND", name: "NetworkProtocol" },
    "Core::Thing" => { kind: "OBJECT_KIND", name: "ClientThing" }
  }.freeze

  REFUSED = {
    "Hash" => "Hash is not a type the API can carry",
    "Symbol" => "Symbol is not a type the API can carry",
    "Object" => "Object is not a type the API can carry",
    "Unregistered" => "ModHelper::Fixtures::Unregistered is not a type the API can carry"
  }.freeze

  def setup
    super
    types = ROWS.keys + REFUSED.keys
    declare(<<~RUBY)
      class Mood < Dagger::Mod::Enum
        member :HAPPY
      end

      module Shape
        extend Dagger::Mod::Interface
      end

      class Unregistered; end

      class Main
        extend Dagger::Mod::Object

      #{types.each_with_index.map { |type, index| "  #: () -> #{type}\n  def t#{index} = nil\n" }.join}
        #: (?mood: Mood) -> void
        def default(mood: Mood::HAPPY) = mood
      end
    RUBY
    @signatures = signatures
    @index = types.each_with_index.to_h
  end

  def main = ModHelper::Fixtures::Main

  def resolved(type)
    signature = @signatures.method_of(main, "t#{@index.fetch(type)}")
    Dagger::Mod::Signatures.resolve(signature.returns, signature.nesting, main)
  end

  def type_ref(type) = Dagger::Mod.registry.type_ref(resolved(type), "Main.t")

  def expected(row) = { name: "", optional: false, elem: nil }.merge(row, elem: row[:elem] && expected(row[:elem]))

  def test_every_row_of_the_type_mapping
    ROWS.each { |type, row| assert_equal expected(row), type_ref(type).to_h, type }
  end

  def test_a_type_the_api_cannot_carry_is_refused_naming_it
    REFUSED.each do |type, message|
      error = assert_raises(Dagger::Mod::RegistrationError, type) { type_ref(type) }
      assert_equal "Main.t: #{message}", error.message
    end
  end

  def test_names_resolve_in_the_lexical_scopes_of_the_annotation
    signature = @signatures.method_of(main, "t#{@index.fetch("Core::Directory")}")

    assert_equal %w[ModHelper::Fixtures::Main ModHelper::Fixtures ModHelper], signature.nesting
    assert_equal "lib/main.rb:#{15 + (2 * @index.fetch("Core::Directory"))}", signature.location
    assert_raises(NameError) { Dagger::Mod::Signatures.resolve("Nope", signature.nesting, main) }
  end

  def test_an_enum_default_resolves_to_its_member_once_loaded
    signature = @signatures.method_of(main, "default")
    default = signature.params.first.default

    assert_equal({ "constant" => "Mood::HAPPY" }, default)
    member = Dagger::Mod::Signatures.constant(default["constant"], signature.nesting)

    assert_same ModHelper::Fixtures::Mood::HAPPY, member
  end
end
