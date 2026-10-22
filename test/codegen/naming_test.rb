require_relative "../test_helper"
require_relative "codegen_helper"

class NamingTest < Minitest::Test
  Naming = RubySdk::Codegen::Naming

  def test_graphql_names_become_snake_case
    assert_equal "with_exec", Naming.method_name("withExec")
    assert_equal "llm_content_block_input", Naming.file_name("LLMContentBlockInput")
    assert_equal "as_json", Naming.method_name("asJSON")
    assert_equal "sha256_sum", Naming.method_name("sha256Sum")
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

  def test_a_name_that_cannot_be_a_constant_is_refused
    assert_raises(RubySdk::Codegen::Error) { Naming.constant("lowercase") }
    assert_equal "GZIP", Naming.constant("GZIP")
  end
end
