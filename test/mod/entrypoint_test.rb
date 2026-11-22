require_relative "mod_helper"
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ruby_sdk/codegen/stand_in"
require "dagger/mod/cli"

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
    assert_equal File.read(File.join(GOLDEN, "main.dang")),
                 Entrypoint.render_main("main", client_version: CLIENT_VERSION)
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
    main = Entrypoint.render_main("main", client_version: CLIENT_VERSION, outside: ["../shared"],
                                          outside_files: ["../Gemfile.common"])

    assert_equal File.read(File.join(GOLDEN, "main-sources.dang")), main
  end

  def test_a_module_without_anything_outside_declares_sources
    main = Entrypoint.render_main("main", client_version: CLIENT_VERSION)

    assert_includes main, "  pub sources(workspace: Workspace!): Directory! {\n"
    assert_includes main, "  pub types: [TypeDef!]! {\n"
    assert_includes main, "  pub call(\n    receiverType: String!,\n"
  end

  def test_the_call_runs_on_the_current_source_and_records_none_of_it
    main = Entrypoint.render_main("main", client_version: CLIENT_VERSION)

    assert_includes main, "RubyModuleBuild(source: currentModule.source, moduleName: moduleName).installed"
    refute_match(/digest\(|sha256:|dagger generate/, main)
  end

  def test_strings_are_quoted_as_json
    types = Entrypoint.render_types(describe)

    assert_includes types, '.withDescription("A \"container\".\n\nBuilt from\\\\a base image.\tTabbed.")'
  end

  def test_the_main_object_alone_has_a_constructor
    assert_equal 1, Entrypoint.render_types(describe).scan(".withConstructor(").size
  end

  def test_a_nullable_argument_is_optional_once
    assert_includes Entrypoint.render_types(describe), '.withArg("who", typeDef.withOptional(true).withKind'
  end

  def test_the_empty_description_renders_the_core_stand_in
    Dagger::Mod.reset_registry!
    declare("class CoreSchema\nextend Dagger::Mod::Object\nend")

    assert_equal RubySdk::Codegen::StandIn::TYPES, Entrypoint.render_types(describe("CoreSchema"))
  end

  # Both runtimes: without it, a nested client gets whatever view the engine gives the module.
  def test_the_call_sets_the_client_version_before_it_runs_the_module
    [Entrypoint.render_main("main", client_version: "v9"),
     Entrypoint.render_main("main", client_version: "v9", outside: ["../shared"])].each do |main|
      assert_includes main, %(  let clientVersion: String! = "v9"\n)
      version = /\.withEnvVariable\("DAGGER_CLIENT_VERSION", clientVersion\)\n/
      assert_match(/#{version}(?:\s*(?:#|\.withEnvVariable).*\n)*\s*\.withExec\(\["ruby"/, main)
    end
  end

  def test_the_entrypoint_command_requires_the_client_version
    error = assert_raises(Dagger::Mod::Error) { Dagger::Mod::CLI.entrypoint({ output: "/nowhere" }) }

    assert_includes error.message, "--client-version"
  end

  # The digest keys the exec on the call, and marks it, and no other exec,
  # as the module process: the install before it is the module's build.
  def test_the_call_declares_the_call_digest_and_marks_its_exec_with_it
    main = Entrypoint.render_main("main", client_version: CLIENT_VERSION)
    install = main.index("let installed = runtime.sync")
    marked = main.index('.withEnvVariable("DAGGER_MODULE_CALL_DIGEST", callDigest ?? "")')
    exec = main.index('.withExec(["ruby", "-rbundler/setup", "sdk/exe/dagger-mod", "call", "--output", ' \
                      '"/dagger/result.json"], stdin: request)')

    assert_includes main, "    callDigest: String,\n  ): JSON! {"
    assert_equal 1, main.scan("DAGGER_MODULE_CALL_DIGEST").size
    assert_operator install, :<, marked
    assert_operator marked, :<, exec
  end

  # The engine builds prebuild ahead of a call, as the module's build: the
  # module's container, its gems installed.
  def test_the_entrypoint_declares_the_install_as_its_prebuild
    main = Entrypoint.render_main("main", client_version: CLIENT_VERSION)

    assert_includes main, "  pub prebuild: File! {\n    runtime.file(\"Gemfile.lock\")\n  }\n"
  end

  # The exec's error is raised as it is when the engine read the function's
  # error from its file; otherwise the dispatcher's last marker line has it.
  def test_the_call_raises_the_function_error
    main = Entrypoint.render_main("main", client_version: CLIENT_VERSION)

    assert_includes main, ".contents rescue {\n        err: GraphQLError => raiseFunctionError(err)\n      }"
    assert_includes main, "functionError: {{message: String, id: String}}"
    assert_includes main, %(let marker = "#{Dagger::Mod::ErrorReport::MARKER}")
    assert_includes main, 'stderr.split("\n")'
  end
end
