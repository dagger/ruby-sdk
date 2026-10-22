require_relative "../test_helper"
require "dagger/mod"

class ModNamingTest < Minitest::Test
  Naming = Dagger::Mod::Naming

  # Values from github.com/iancoleman/strcase v0.3.0, which the engine uses.
  def test_to_camel_matches_the_engine
    {
      "greeter" => "Greeter", "my-module" => "MyModule", "MyModule" => "MyModule", "module3" => "Module3",
      "p11lib" => "P11Lib", "ruby-sdk" => "RubySdk", "HTTPServer" => "Httpserver", "LLM" => "Llm",
      "a.b_c d" => "ABCD", "x9y" => "X9Y", " spaced " => "Spaced"
    }.each { |name, camel| assert_equal camel, Naming.to_camel(name), name }
  end

  def test_api_names_are_lower_camel_case
    assert_equal "howMany", Naming.api_name(:how_many)
    assert_equal "x", Naming.api_name(:x)
    assert_equal "sha256Sum", Naming.api_name("sha256_sum")
  end

  def test_the_module_file_is_the_snake_case_module_name
    {
      "my-module" => "my_module", "MyModule" => "my_module", "myModule" => "my_module", "module3" => "module3",
      "e2e" => "e2e", "p11lib" => "p11lib", "s3-bucket" => "s3_bucket", "HTTPServer" => "http_server",
      "a.b c" => "a_b_c", " spaced- " => "spaced"
    }.each { |name, file| assert_equal "lib/#{file}.rb", Naming.module_file(name), name }
  end
end
