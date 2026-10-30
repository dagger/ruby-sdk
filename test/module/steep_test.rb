require_relative "scope_helper"
require "ruby_sdk/steep"

class SteepTest < Minitest::Test
  MANIFEST = RubySdk::Manifest.render("clean")

  # What generation writes into a module: its manifest, the SDK's marker on
  # sdk/, a Gemfile; the template adds the Steepfile.
  def authored(root, steepfile: true)
    files = { "dagger-module.toml" => MANIFEST, "Gemfile" => "", "sdk/.dagger-generated" => "sdk\n",
              "lib/clean.rb" => "" }
    files["Steepfile"] = "" if steepfile
    files.transform_keys { root == "." ? it : "#{root}/#{it}" }
  end

  # The SDK module's own root, a plain scope with a client, a module of
  # another SDK on a Dang entrypoint, and a module without a Gemfile.
  OTHERS = {
    "dagger-module.toml" => %(name = "ruby-sdk"\n\n[runtime]\nsource = "dang"\n), "Gemfile" => "",
    "sdk/.dagger-generated" => "sdk\n",
    "plain/Gemfile" => "", "plain/sdk/.dagger-generated" => "sdk\n",
    "python/dagger-module.toml" => %(name = "python"\n\n[entrypoint]\nkind = "dang"\nsource = "./sdk/entrypoint"\n),
    "python/pyproject.toml" => "", "python/sdk/entrypoint/main.dang" => "",
    "bare/dagger-module.toml" => MANIFEST, "bare/sdk/.dagger-generated" => "sdk\n"
  }.freeze

  def steep(files, cwd: "/")
    RubySdk::Steep.new(ws: FakeWorkspace.new(FakeTree.new(files), cwd), image: "ruby", target_version: "v1.0.0-beta.21")
  end

  def test_every_module_this_sdk_generated_is_found_and_nothing_else
    files = OTHERS.merge(authored(".dagger/modules/clean")).merge(authored("apps/nested/broken"))

    assert_equal %w[.dagger/modules/clean apps/nested/broken], steep(files, cwd: "/apps").modules
  end

  def test_one_module_is_the_nearest_at_or_above_a_path_from_the_cwd
    files = OTHERS.merge(authored("apps/web"))

    assert_equal "apps/web", steep(files, cwd: "/apps").module_at("web/lib")
    assert_equal "apps/web", steep(files, cwd: "/apps/web/lib").module_at(".")
  end

  def test_one_module_is_refused_when_it_is_not_this_sdks_or_there_is_none
    files = OTHERS.merge(authored("apps/web"))
    other = assert_raises(RubySdk::Error) { steep(files).module_at("python/sdk") }
    none = assert_raises(RubySdk::Error) { steep(files.except("dagger-module.toml")).module_at("plain") }

    assert_equal "python is a module, but not a Ruby module this SDK generated", other.message
    assert_equal "no module at or above plain: no dagger-module.toml there or above", none.message
  end

  # Steep runs in the engine; here every module reports the outcome given.
  class Recorded < RubySdk::Steep
    def initialize(outcomes, **)
      super(**)
      @outcomes = outcomes
    end

    private

    def outcome(root) = @outcomes.fetch(root)
  end

  def outcome(root, code, output = "", refusals: [], steep: true)
    RubySdk::Steep::Outcome.new(root, refusals, steep, code, output)
  end

  def recorded(files, outcomes)
    Recorded.new(outcomes, ws: FakeWorkspace.new(FakeTree.new(files), "/"), image: "ruby",
                           target_version: "v1.0.0-beta.21")
  end

  def test_every_failing_module_is_reported_with_its_output_and_exit_code
    files = authored("a").merge(authored("b")).merge(authored("c")).merge(authored("d", steepfile: false))
    outcomes = { "a" => outcome("a", 1, "a: wrong type\n"), "b" => outcome("b", 0, "fine"),
                 "c" => outcome("c", 2, "c: no steep\n"), "d" => outcome("d", 0, steep: false) }
    error = assert_raises(RubySdk::Error) { recorded(files, outcomes).check }

    assert_equal <<~TEXT.chomp, error.message
      The Steep check failed in 2 of 4 Ruby modules: a, c

      a: bundle exec steep check exited 1
      a: wrong type

      c: bundle exec steep check exited 2
      c: no steep

      checked: a, b, c, d
      generation checks ok: a, b, c, d
      steep ok: b
      steep skipped, no Steepfile: d
    TEXT
  end

  # Steep passes on a def without an annotation; generation does not.
  def test_what_generation_refuses_fails_the_check_even_where_steep_passes
    refusal = "a: describing the module failed: dagger-mod: Dagger::Mod::RegistrationError: lib/a.rb:31: A.hello " \
              "has no annotation that generation read; write its type on the line above the def, as " \
              "#: (name: String) -> String"
    outcomes = { "a" => outcome("a", 0, "No type error detected.", refusals: [refusal]), "b" => outcome("b", 0) }
    error = assert_raises(RubySdk::Error) { recorded(authored("a").merge(authored("b")), outcomes).check }

    assert_equal "The Steep check failed in 1 of 2 Ruby modules: a\n\na: dagger generate refuses it\n#{refusal}\n\n" \
                 "checked: a, b\ngeneration checks ok: b\nsteep ok: a, b", error.message
  end

  # A module without a Steepfile still gets generation's checks.
  def test_a_passing_check_says_generation_and_steep_accept_what_it_checked
    files = authored("a").merge(authored("d", steepfile: false))
    checker = recorded(files, { "a" => outcome("a", 0), "d" => outcome("d", 0, steep: false) })

    _, err = capture_io { checker.check }
    assert_equal "ruby-sdk: checked: a, d\ngeneration checks ok: a, d\nsteep ok: a\nsteep skipped, no Steepfile: d\n",
                 err
    _, one = capture_io { checker.check("d") }
    assert_equal "ruby-sdk: checked: d\ngeneration checks ok: d\nsteep ok: none\nsteep skipped, no Steepfile: d\n", one
  end

  # The scope checks are generation's own, with its words.
  def test_the_scope_refusals_are_generations
    checker = steep(authored("a"))
    manifest = checker.send(:scope_refusal, "a", FakeTree.new(authored(".").merge("dagger.json" => "{}")), [])
    core = checker.send(:scope_refusal, "a", FakeTree.new(authored(".").merge("clients/core/x.rb" => "")), [])

    assert_equal "a/dagger.json is a manifest of an earlier Dagger; the Ruby SDK writes dagger-module.toml only, so " \
                 "remove dagger.json, then run dagger generate again", manifest
    assert_equal "clients/core/ exists in a and was not written by dagger generate as its core; generation replaces " \
                 "it whole, so move or rename it, then run dagger generate again", core
    assert_nil checker.send(:scope_refusal, "a", FakeTree.new(authored(".")), [])
  end

  # The check writes the signatures generation would, from the same files.
  def test_the_signatures_are_read_from_lib_as_generation_reads_them
    tree = FakeTree.new("lib/a.rb" => "class A\n  #: () -> String\n  def hi = \"\"\nend\n", "test/a_test.rb" => "x")
    signatures = JSON.parse(RubySdk::Signatures.json(tree))

    assert_equal ["lib/a.rb"], signatures.keys
    assert_equal "String", signatures.dig("lib/a.rb", 0, "methods", "hi", "returns")
  end

  def test_the_manifest_names_the_generated_entrypoint
    assert RubySdk::Manifest.entrypoint?(MANIFEST)
    refute RubySdk::Manifest.entrypoint?(OTHERS.fetch("dagger-module.toml"))
    refute RubySdk::Manifest.entrypoint?(%(name = "x"\n[entrypoint]\nkind = "dang"\nsource = "./elsewhere"\n))
    refute RubySdk::Manifest.entrypoint?("name = [\n")
  end

  # The check names what generation would refuse: a passing check means dagger generate accepts the module.
  def test_the_generation_check_includes_the_dang_toml_refusals
    files = authored(".").merge("sdk/entrypoint/dang.toml" => %([imports.Dagger]\npath = "./mine"\n))
    check = steep(files)
    dir = FakeTree.new(files)

    assert_includes check.send(:scope_refusal, ".", dir, []), "imports.Dagger.path"
  end

  # The check installs the development group in its own container; the
  # module's container never does.
  def test_only_the_development_install_drops_bundle_without
    build = Dagger::Mod::Build.new(image: "ruby", module_name: "clean", gemspecs: [])

    assert_equal "development", build.env["BUNDLE_WITHOUT"]
    refute build.env(development: true).key?("BUNDLE_WITHOUT")
    assert_includes build.to_dang, %(.withEnvVariable("BUNDLE_WITHOUT", "development"))
  end
end
