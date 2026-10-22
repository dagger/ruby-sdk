require_relative "mod_helper"
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ruby_sdk/codegen/stand_in"

class EntrypointTest < Minitest::Test
  include ModHelper

  FIXTURE = File.expand_path("../fixtures/entrypoint", __dir__)
  GOLDEN = File.expand_path("../golden/mod", __dir__)
  Entrypoint = Dagger::Mod::Entrypoint

  def setup
    super
    declare(File.read(File.join(FIXTURE, "lib/main.rb")))
  end

  def test_golden_types_and_main
    assert_equal File.read(File.join(GOLDEN, "types.dang")), Entrypoint.render_types(describe)
    assert_equal File.read(File.join(GOLDEN, "main.dang")), Entrypoint.render_main("main")
  end

  # What Steep needs beside the annotations: the readers and initializer of
  # each object's fields, and each enum's members.
  def test_golden_module_rbs
    describe

    assert_equal File.read(File.join(GOLDEN, "module.rbs")), Entrypoint.render_rbs(Dagger::Mod.registry)
  end

  # What the build reads outside the module: sources returns it for the
  # engine to load with the module, which builds from its context directory;
  # types and call then get no workspace.
  def test_sources_make_the_module_build_from_its_context
    main = Entrypoint.render_main("main", outside: ["../shared"], outside_files: ["../Gemfile.common"])

    assert_equal File.read(File.join(GOLDEN, "main-sources.dang")), main
  end

  def test_a_module_without_anything_outside_keeps_the_workspace_contract
    main = Entrypoint.render_main("main")

    refute_includes main, "sources"
    assert_includes main, "  pub types(workspace: Workspace!): [TypeDef!]! {\n"
    assert_includes main, "  pub call(\n    workspace: Workspace!,\n    receiverType: String!,\n"
  end

  def test_the_call_runs_on_the_current_source_and_records_none_of_it
    main = Entrypoint.render_main("main")

    assert_includes main, "RubyModuleBuild(source: currentModule.source, moduleName: moduleName).installed"
    refute_match(/digest\(|sha256:|dagger generate/, main)
  end

  def test_strings_are_quoted_as_json
    types = Entrypoint.render_types(describe)

    assert_includes types, '.withDescription("A \"container\".\n\nBuilt from\\\\a base image.\tTabbed.")'
  end

  def test_the_main_object_alone_has_a_constructor_and_no_function_has_a_cache_policy
    types = Entrypoint.render_types(describe)

    assert_equal 1, types.scan(".withConstructor(").size
    refute_includes types, "withCachePolicy"
  end

  def test_a_nullable_argument_is_optional_once
    assert_includes Entrypoint.render_types(describe), '.withArg("who", typeDef.withOptional(true).withKind'
  end

  def test_the_empty_description_renders_the_core_stand_in
    Dagger::Mod.reset_registry!
    declare("class CoreSchema\nextend Dagger::Mod::Object\nend")

    assert_equal RubySdk::Codegen::StandIn::TYPES, Entrypoint.render_types(describe("CoreSchema"))
  end

  def test_the_call_declares_the_call_digest_and_sends_it
    main = Entrypoint.render_main("main")

    assert_includes main, "    callDigest: String,\n  ): JSON! {"
    assert_includes main, "      callDigest: callDigest,\n"
    assert_includes main, '.withExec(["ruby", "-rbundler/setup", "sdk/exe/dagger-mod", "call", "--output", ' \
                          '"/dagger/result.json"], stdin: request)'
  end
end
