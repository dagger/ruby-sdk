require_relative "../test_helper"
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__),
                   File.expand_path("../../tmp/codegen/core/lib", __dir__)
require "ruby_sdk"

require "ruby_sdk/call"

# The SDK module is a Dang module whose functions run lib/ruby_sdk.rb: the
# Dang declares the API, which the Ruby half must answer.
class SdkModuleTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def dang(file = "ruby-sdk.dang") = File.read(File.join(ROOT, file))

  def manifest = File.read(File.join(ROOT, "dagger-module.toml"))

  # RubySdk's fields and the functions every Dang type calls into Ruby; mod
  # is Dang's alone, the module a function such as steep then runs on.
  def test_the_dang_module_declares_what_ruby_sdk_answers
    ruby = RubySdk.public_instance_methods(false).map { Dagger::Mod::Naming.api_name(it) }
    called = Dir[File.join(ROOT, "*.dang")].flat_map { File.read(it).scan(/ruby\.call\("(\w+)"/).flatten }.uniq

    assert_equal (ruby + ["mod"]).sort, dang.scan(/^  pub (\w+)/).flatten.sort
    assert_equal %w[findClientRoot generateScope steep], called.sort
    assert_equal %w[template rubyVersion].sort, (ruby - called).sort
    assert_match(/^  pub steep\(ws: Workspace!\): Void @check \{$/, dang)
    assert_match(/^  pub steep: Void \{$/, dang("mod.dang"))
  end

  def test_a_call_names_a_function_of_the_ruby_half
    request = { "moduleSource" => "src", "template" => "default", "rubyVersion" => "", "targetVersion" => "v1",
                "function" => "nope", "args" => "{}" }

    assert_raises(RubySdk::Error) { RubySdk::Call.run(request) }
  ensure
    Dagger::Mod.module_source_id = nil
  end

  def test_the_manifest_is_a_dang_module_on_a_pinned_api
    assert_match(/^\[runtime\]\nsource = "dang"\n/, manifest)
    refute_match(/^\[entrypoint\]/, manifest)
    assert_match(/^engineVersion = "v1\.0\.0-beta\.20"$/, manifest)
  end

  # The Ruby half's nested client would otherwise see the engine's API, not the
  # pinned one its committed core was generated for.
  def test_the_ruby_half_declares_the_pinned_api
    half = dang("ruby-half.dang")
    pinned = manifest[/^engineVersion = "([^"]+)"$/, 1]

    assert_includes half, %(  let clientVersion: String! = "#{pinned}"\n)
    assert_match(/\.withEnvVariable\("DAGGER_CLIENT_VERSION", clientVersion\)\n\s*\.withExec/, half)
  end

  # Two channels: clients/core stays on the module's pin, whatever generation targets.
  def test_the_generated_target_is_one_value_the_ruby_half_receives
    target = dang[/^  let targetVersion: String! = "([^"]+)"$/, 1]

    assert_equal "v1.0.0-beta.21", target
    assert_includes dang, "RubyHalf(template: template, rubyVersion: rubyVersion, targetVersion: targetVersion)"
    assert_includes dang("ruby-half.dang"), "      targetVersion: targetVersion,\n"
    assert_equal(1, Dir[File.join(ROOT, "*.dang")].sum { File.read(it).scan(target).size })
  end

  def test_generate_scope_writes_the_config_through_the_helper
    assert_includes dang, %(.withVersion("#{RubySdk::DangConfig::LANGUAGE}")\n)
    assert_includes dang, %(.withDaggerImport(name: "#{RubySdk::DangConfig::IMPORT}", version: targetVersion)\n)
    assert_includes dang, %(let dangConfigPath: String! = "#{RubySdk::DangConfig::FILE}"\n)
  end

  def test_the_helper_is_pinned_to_its_release
    assert_includes manifest, <<~TOML
      name = "sdk-helpers"
      source = "github.com/dagger/sdk-helpers@31dafd0c74d9a08faa00c09dce87a5af072e7a9d"
    TOML
  end

  # Its source is what the Ruby half reads, and nothing else.
  def test_the_module_source_holds_what_the_sdk_reads
    included = manifest[/^include = \[\n(.*?)^\]/m, 1].scan(/"([^"]+)"/).flatten

    assert_equal %w[!* dagger-module.toml ruby-sdk.dang ruby-half.dang mod.dang Gemfile Gemfile.lock dagger.gemfile lib
                    sdk clients templates images], included
    assert_equal Dir[File.join(ROOT, "*.dang")].map { File.basename(it) }.sort, included.grep(/\.dang\z/).sort
  end
end
