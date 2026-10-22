require_relative "../test_helper"
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ruby_sdk/signatures"

class TemplatesTest < Minitest::Test
  ROOT = File.expand_path("../../templates", __dir__)

  def sources = Dir.children(ROOT).sort.to_h { [it, File.read(File.join(ROOT, it, "lib", "{{file}}.rb.tmpl"))] }

  def test_every_template_includes_the_client_roots_in_its_main_class
    assert_equal %w[default empty], sources.keys
    sources.each do |name, source|
      assert_includes source, %(require "dagger/clients/roots"\n), name
      assert_match(/^  extend Dagger::Mod::Object\n(?:  #.*\n)*  include Dagger::Clients::Roots\n/, source, name)
    end
  end

  # Types stay constants; calls go through the roots' methods.
  def test_the_default_template_calls_core_by_its_method
    source = sources.fetch("default")

    assert_includes source, "    core.container.from("
    refute_match(/Dagger::Clients::\w+\.\w/, source)
  end

  # The module's container installs without the development group.
  def test_every_template_ships_steep_for_development_and_a_steepfile
    Dir.children(ROOT).each do |name|
      assert_match(/^group :development do\n  gem "steep"/, File.read(File.join(ROOT, name, "Gemfile")), name)
      assert_match(/^  check "lib", inline: true$/, File.read(File.join(ROOT, name, "Steepfile")), name)
    end
  end

  def test_the_default_template_reads_as_annotated_fields_and_functions
    source = sources.fetch("default").gsub("{{class}}", "Main")
    scope = RubySdk::Signatures.parse("lib/main.rb" => source).fetch("lib/main.rb").first
    defs = scope.fetch("methods").values + scope.fetch("singleton_methods").values

    assert_equal %w[source base_image_address], scope.fetch("fields").keys
    assert(scope.fetch("fields").values.all? { it.key?("type") })
    assert_equal([["container", "::Dagger::Clients::Core::Container"]],
                 scope.fetch("methods").map { |name, record| [name, "::#{record["returns"]}"] })
    refute(defs.any? { it.key?("refused") })
  end
end
