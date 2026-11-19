require_relative "../test_helper"
require "dagger/mod"

class ModNamingTest < Minitest::Test
  Naming = Dagger::Mod::Naming

  def test_the_module_file_is_the_snake_case_module_name
    {
      "my-module" => "my_module", "MyModule" => "my_module", "myModule" => "my_module", "module3" => "module3",
      "e2e" => "e2e", "p11lib" => "p11lib", "s3-bucket" => "s3_bucket", "HTTPServer" => "http_server",
      "a.b c" => "a_b_c", " spaced- " => "spaced"
    }.each { |name, file| assert_equal "lib/#{file}.rb", Naming.module_file(name), name }
  end
end
