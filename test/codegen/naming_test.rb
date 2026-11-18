require_relative "../test_helper"
require_relative "codegen_helper"

class NamingTest < Minitest::Test
  Naming = RubySdk::Codegen::Naming

  def setup
    @names = Naming.names
    Naming.names = { "experimentalWithAllGPUs" => "experimental_with_all_gpus", "LLMContentBlockInput" => "llm_input",
                     "send" => "send", "class" => "class", "query" => "query", "end" => "end", "alias" => "alias",
                     "module" => "module", "refPin" => "ref_pin" }
  end

  def teardown
    Naming.names = @names
  end

  def test_graphql_names_become_the_engines_snake_case
    assert_equal "experimental_with_all_gpus", Naming.method_name("experimentalWithAllGPUs")
    assert_equal "llm_input", Naming.file_name("LLMContentBlockInput")
  end

  def test_a_name_the_engine_was_not_asked_for_is_refused
    error = assert_raises(RubySdk::Codegen::Error) { Naming.method_name("withExec") }
    assert_equal 'the engine was not asked to name "withExec"', error.message
  end

  def test_methods_every_object_needs_are_not_replaced
    assert_equal "send_", Naming.method_name("send")
    assert_equal "class_", Naming.method_name("class")
    assert_equal "query_", Naming.method_name("query")
    assert_equal "end", Naming.method_name("end")
  end

  def test_keyword_arguments_get_a_trailing_underscore
    assert_equal "alias_", Naming.argument_name("alias")
    assert_equal "module_", Naming.argument_name("module")
    assert_equal "ref_pin", Naming.argument_name("refPin")
  end

  def test_the_names_are_every_type_field_argument_and_input_field
    document = { "__schema" => { "types" => [
      { "name" => "Query", "fields" => [{ "name" => "withGPU", "args" => [{ "name" => "deviceID" }] }] },
      { "name" => "BuildArg", "inputFields" => [{ "name" => "value" }] }, { "name" => "__Type", "fields" => [] }
    ] } }
    assert_equal %w[BuildArg Query deviceID value withGPU], Naming.identifiers([document])
  end

  def test_a_name_that_cannot_be_a_constant_is_refused
    assert_raises(RubySdk::Codegen::Error) { Naming.constant("lowercase") }
    assert_equal "GZIP", Naming.constant("GZIP")
  end
end
