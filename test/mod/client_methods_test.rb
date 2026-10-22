require_relative "mod_helper"

# The generated Dagger::Clients::Roots, as a scope with core and a client
# greeter would have it.
class ClientMethodsTest < Minitest::Test
  include ModHelper

  def setup
    super
    ::Dagger.const_set(:Clients, Module.new) unless ::Dagger.const_defined?(:Clients)
    ::Dagger::Clients.const_set(:Roots, Module.new do
      def self.clients = { core: "core", greeter: "greeter" }.freeze

      private

      def core = :core
      def greeter = :greeter
    end)
  end

  def teardown
    ::Dagger::Clients.send(:remove_const, :Roots)
    super
  end

  def main(body)
    declare(<<~RUBY)
      class Main
        extend Dagger::Mod::Object
        include Dagger::Clients::Roots

      #{body}
      end
    RUBY
  end

  def refusal(body)
    main(body)
    assert_raises(Dagger::Mod::RegistrationError) { describe }.message
  end

  def given(method) = %(the method #{method} that Dagger::Clients::Roots gives the client "#{method}")

  def test_the_client_methods_are_private_and_are_no_functions
    main(%(function\n#: () -> String\ndef hello = "\#{greeter} \#{core}"))
    functions = object(describe, "Main").functions.map(&:name)

    assert_equal ["hello"], functions
    assert_equal "greeter core", ModHelper::Fixtures::Main.new.hello
    assert_raises(NoMethodError) { ModHelper::Fixtures::Main.new.core }
  end

  def test_a_field_named_like_a_client_method_is_refused
    assert_equal "ModHelper::Fixtures::Main: the field greeter has the name of #{given("greeter")}; rename it",
                 refusal("field :greeter #: String")
  end

  def test_a_function_named_like_a_client_method_is_refused
    assert_equal "ModHelper::Fixtures::Main: the function core has the name of #{given("core")}; rename it",
                 refusal("function\n#: () -> String\ndef core = \"\"")
  end

  def test_a_constructor_argument_named_like_a_client_method_is_refused
    assert_equal "ModHelper::Fixtures::Main: the constructor argument core has the name of #{given("core")}; " \
                 "rename it",
                 refusal("constructor\n#: (core: String) -> instance\ndef self.create(core:) = new")
  end

  def test_a_private_method_named_like_a_client_method_is_refused
    assert_equal "ModHelper::Fixtures::Main: ModHelper::Fixtures::Main#greeter hides #{given("greeter")}; rename it",
                 refusal("private\ndef greeter = nil")
  end

  def test_a_class_without_the_roots_keeps_any_name
    declare("class Main\nextend Dagger::Mod::Object\nfield :core #: String\nend")

    assert_equal ["core"], object(describe, "Main").fields.map(&:name)
  end
end
