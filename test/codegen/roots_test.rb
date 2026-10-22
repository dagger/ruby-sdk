require_relative "../test_helper"
require_relative "codegen_helper"

class RootsTest < Minitest::Test
  include CodegenHelper

  GOLDEN_ROOTS = File.expand_path("../golden/codegen-roots", __dir__)
  Roots = RubySdk::Codegen::Roots
  Schema = RubySdk::Codegen::Schema

  def roots_of(*names) = Roots.files(names.map { [schema_of(it), it] })

  # The module's schema, its constructor field named field, as the engine
  # names it from the module's name.
  def schema_of(module_name, field = module_name)
    document = client_document(module_name)
    query = document["__schema"]["types"].find { it["name"] == "Query" }
    query["fields"].find { it["name"] == module_name }["name"] = field
    Schema.new(document)
  end

  def test_golden_files
    ROOTS_GOLDEN_FILES.each { assert_equal File.read(File.join(GOLDEN_ROOTS, it)), roots_files.fetch(it), it }
  end

  def test_a_scope_without_clients_has_core_alone
    ruby = Roots.files([]).fetch("lib/dagger/clients/roots.rb")

    assert_includes ruby, "def self.clients = { core: \"core\" }.freeze"
    assert_includes ruby, "def core(session: nil) = ::Dagger::Clients::Core.core(session:)"
  end

  # The engine's constructor field for the module, in snake case.
  def test_a_client_method_is_its_entry_point_in_snake_case
    { "greetings" => "greetings", "myModule" => "my_module", "p11Lib" => "p11_lib", "s3Bucket" => "s3_bucket",
      "httpserver" => "httpserver", "module3" => "module3", "e2e" => "e2e" }.each do |field, method|
      assert_equal method, Roots.method_name(field), field
    end
  end

  def test_the_method_passes_every_argument_through_and_is_typed_as_the_entry_point
    ruby = roots_files.fetch("lib/dagger/clients/roots.rb")
    rbs = roots_files.fetch("sig/dagger/clients/roots.rbs")

    assert_includes ruby, "def greeter(greeting: nil, session_: nil, session: nil)\n        " \
                          "::Dagger::Clients::Greeter.greeter(greeting:, session_:, session:)\n"
    assert_includes rbs, "def greeter: (?greeting: ::String?, ?session_: ::String?, ?session: ::Dagger::Session?) " \
                         "-> ::Dagger::Clients::Greeter::Greeter"
    assert_operator ruby.index("private\n"), :<, ruby.index("def core(")
  end

  def test_a_method_that_every_object_or_a_keyword_has_is_refused
    { "tap" => "which every Ruby object has (Kernel#tap)", "display" => "which every Ruby object has (Kernel#display)",
      "format" => "which every Ruby object has (Kernel#format)",
      "begin" => "which is a Ruby keyword" }.each do |name, why|
      error = assert_raises(RubySdk::Codegen::Error) { roots_of(name) }

      assert_equal %(the client "#{name}" would get the method #{name}, #{why}), error.message
    end
    assert_equal "is core's", Roots.refusal("core")
  end

  def test_two_clients_with_one_method_are_refused
    clients = [[schema_of("my_module", "myModule"), "my_module"], [schema_of("myModule"), "myModule"]]
    error = assert_raises(RubySdk::Codegen::Error) { Roots.files(clients) }

    assert_equal %(the clients "my_module" and "myModule" would both get the method my_module), error.message
  end

  def test_roots_is_not_a_client_name
    error = assert_raises(RubySdk::Codegen::Error) { RubySdk::Codegen::Naming.client_file("roots") }

    assert_equal %(client name "roots" is taken by the scope's client roots), error.message
  end
end
