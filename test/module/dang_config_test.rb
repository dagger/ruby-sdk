require_relative "../test_helper"
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ruby_sdk/dang_config"

class DangConfigTest < Minitest::Test
  DangConfig = RubySdk::DangConfig
  TARGET = "v1.0.0-beta.21".freeze

  def objections(toml) = DangConfig.objections(toml, TARGET)

  def hidden(toml) = DangConfig.hidden(toml, TARGET)

  def test_what_the_sdk_manages_or_keeps_is_no_objection
    ["", %(dang = "2.1"\n), %([imports.Dagger]\ndagger = true\n), %([imports.Dagger]\ndagger = "v1.0.0-beta.19"\n),
     %([imports.Dagger]\ndagger = "v1.0.0-beta.22"\n), %([imports.Dagger]\nendpoint = ""\nservice = ["a"]\n),
     %([imports.Lib]\npath = "./lib"\n), %([imports.Other]\ndagger = true\n),
     %([imports.Other]\ndagger = "#{TARGET}"\n), %(other = 1\n)].each do |toml|
      assert_empty objections(toml), toml
    end
  end

  def test_what_the_helper_would_lose_or_the_target_contradicts_is_named
    {
      %(dang = "2.0"\n) => %(dang = "2.0"),
      %(dang = 2\n) => "dang = 2",
      %(imports = 1\n) => "imports is not a table",
      %(imports.Dagger = "x"\n) => "imports.Dagger is not a table",
      %([imports.Dagger]\npath = "./mine"\n) => "imports.Dagger.path",
      %([imports.Dagger]\nendpoint = "http://localhost"\ndagger = true\n) => "imports.Dagger.endpoint",
      %([imports.Other]\ndagger = "v1.0.0-beta.19"\n) => %(imports.Other.dagger = "v1.0.0-beta.19"),
      "name = [\n" => "not valid TOML"
    }.each do |toml, named|
      found = objections(toml)

      assert_equal 1, found.size, toml
      assert_includes found.first, named
    end
  end

  def test_an_ancestor_the_generated_file_stands_for_hides_nothing
    ["", %(dang = "2.1"\n), %([imports.Dagger]\ndagger = true\n), %([imports.Dagger]\ndagger = "#{TARGET}"\n)]
      .each { |toml| assert_empty hidden(toml), toml }
  end

  def test_what_an_ancestor_sets_beyond_it_is_named
    {
      %(dang = "2.0"\n) => ["dang"],
      %(other = 1\n) => ["other"],
      %(imports = 1\n) => ["imports"],
      %([imports.Dagger]\ndagger = "v1.0.0-beta.19"\n) => ["imports.Dagger"],
      %([imports.Dagger]\ndagger = true\nservice = ["a"]\n) => ["imports.Dagger"],
      %([imports.Lib]\npath = "./lib"\n) => ["imports.Lib"]
    }.each { |toml, named| assert_equal named, hidden(toml), toml }
    assert_includes hidden("name = [\n").first, "not valid TOML"
  end
end
