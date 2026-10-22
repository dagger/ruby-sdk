require_relative "mod_helper"

class InterfaceTest < Minitest::Test
  include ModHelper

  # Answers every query with the data it is given, and keeps the documents.
  class FakeConnection
    attr_reader :documents

    def initialize(data)
      @data = data
      @documents = []
    end

    def execute(document)
      @documents << document
      @data
    end
  end

  DUCK = <<~RUBY.freeze
    class Mood < Dagger::Mod::Enum
      member :HAPPY
      member :SAD
    end

    module Duck
      extend Dagger::Mod::Interface

      description "Something that quacks."

      function "Quack."
      #: (?times: Integer) -> String
      def quack(times: 1) = raise(NotImplementedError)

      function
      #: () -> Duck
      def itself_again = nil

      function
      #: () -> Array[Duck]
      def mob = nil

      function
      #: () -> Mood
      def mood = nil

      function
      #: () -> String?
      def nickname = nil
    end

    class Main
      extend Dagger::Mod::Object

      function
      #: (duck: Duck) -> Duck
      def pass(duck:) = duck
    end
  RUBY

  def setup
    super
    declare(DUCK)
    annotate
  end

  def test_an_interface_is_described_with_its_functions
    duck = object(describe, "Duck")

    assert duck.interface
    assert_empty duck.fields
    assert_nil duck.constructor
    assert_equal %w[itselfAgain mob mood nickname quack], duck.functions.map(&:name).sort
    assert_equal "INTERFACE_KIND", function(describe, "Main", "pass").returns.kind
    assert_equal "INTERFACE_KIND", function(describe, "Duck", "mob").returns.elem.kind
  end

  def test_an_interface_renders_with_with_interface
    types = Dagger::Mod::Entrypoint.render_types(describe)

    assert_includes types, 'typeDef.withInterface("Duck", description: "Something that quacks.")'
    assert_includes types, '.withArg("duck", typeDef.withInterface("Duck"))'
  end

  def test_an_interface_function_cannot_return_a_module_object
    declare(<<~RUBY)
      module Maker
        extend Dagger::Mod::Interface

        function
        #: () -> Main
        def make = nil
      end
    RUBY

    error = assert_raises(Dagger::Mod::RegistrationError) { describe }
    assert_match(/Maker: an interface function cannot return the module object Main/, error.message)
  end

  def test_an_interface_argument_becomes_a_binding_loaded_as_a_node
    convert = Dagger::Mod::Convert.new(Dagger::Mod.registry)
    duck = convert.input("duck-id", ModHelper::Fixtures::Duck, "pass(duck)")

    assert_equal "Node", duck.class.graphql_name
    assert_equal "duck-id", duck.id
    assert_equal "duck-id", convert.output(duck, ModHelper::Fixtures::Duck, "pass result")
  end

  def test_a_binding_runs_leaves_and_chains_objects
    data = { "node" => { "__typename" => "Mallard", "quack" => "quack quack", "mood" => "SAD", "nickname" => nil } }
    connection = FakeConnection.new(data)
    session = Dagger::Session.new(connection)
    klass = Dagger::Mod::Interface.binding(ModHelper::Fixtures::Duck, Dagger::Mod.registry)
    duck = klass.new(Dagger::QueryBuilder.new(session:).node("duck-id", "Node"))

    assert_equal "quack quack", duck.quack(times: 2)
    assert_match(/\.\.\. on Node \{\s+__typename/, connection.documents.first)
    assert_match(/node\(id: "duck-id"\) \{\s+\.\.\. on Mallard \{\s+quack\(times: 2\)/, connection.documents.last)
    assert_equal ModHelper::Fixtures::Mood::SAD, duck.mood
    assert_nil duck.nickname
    duck.quack
    assert_match(/quack\(times: 1\)/, connection.documents.last)
    assert_equal(1, connection.documents.count { it.include?("__typename") })
  end

  def test_a_binding_chains_an_interface_result
    connection = FakeConnection.new({ "node" => { "__typename" => "Mallard" } })
    klass = Dagger::Mod::Interface.binding(ModHelper::Fixtures::Duck, Dagger::Mod.registry)
    duck = klass.new(Dagger::QueryBuilder.new(session: Dagger::Session.new(connection)).node("duck-id", "Node"))

    assert_instance_of klass, duck.itself_again
    assert_match(/\.\.\. on Mallard \{\s+itselfAgain/, duck.itself_again.query.document)
  end
end
