require_relative "../test_helper"
require "dagger/mod"

class BuildTest < Minitest::Test
  GOLDEN = File.expand_path("../golden/mod/build.dang", __dir__)

  GEMSPECS = %w[sdk/dagger-sdk.gemspec clients/core/dagger-clients-core.gemspec].freeze

  def build = Dagger::Mod::Build.new(image: "ruby:4.0@sha256:#{"0" * 64}", module_name: "my-module", gemspecs: GEMSPECS)

  def test_golden_build_dang
    assert_equal File.read(GOLDEN), build.to_dang
  end

  def test_the_rendered_build_reads_only_its_arguments
    refute_includes build.to_dang, "currentModule"
    assert_includes build.to_dang, "type RubyModuleBuild {"
    assert_includes build.to_dang, "pub installed: Container!"
  end

  def test_the_container_excludes_only_the_installed_gems
    assert_equal %w[.bundle vendor/bundle], Dagger::Mod::Build::EXCLUDES
    assert_includes build.to_dang, '.withDirectory("/src", source, exclude: [".bundle", "vendor/bundle"])'
  end

  def test_the_module_is_named_in_the_environment
    assert_equal({ "DAGGER_MODULE" => "my-module", "DAGGER_MAIN_OBJECT" => "MyModule",
                   "DAGGER_MODULE_FILE" => "lib/my_module.rb" },
                 build.env.slice("DAGGER_MODULE", "DAGGER_MAIN_OBJECT", "DAGGER_MODULE_FILE"))
  end

  # Bundler's temporary files are named by process ID, which repeats across
  # containers: builds that run at once must not share a cache directory.
  def test_each_module_and_its_development_install_have_a_bundler_cache_of_their_own
    assert_equal "/cache/bundle/my-module", build.env["BUNDLE_USER_CACHE"]
    assert_equal "/cache/bundle/my-module-development", build.env(development: true)["BUNDLE_USER_CACHE"]
    assert_includes build.to_dang, '.withEnvVariable("BUNDLE_USER_CACHE", "/cache/bundle/" + moduleName)'
  end

  # An edit to lib/ must not reinstall the gems: the install sees the
  # Gemfiles and gemspecs alone, by content, and the rest of the source
  # arrives after it.
  def test_the_gems_install_before_the_rest_of_the_source
    steps = build.to_dang[/^    container\n(.*?)^  }/m, 1].lines.map(&:strip).last(3)
    files = build.to_dang[/let dependencies = \[\n(.*?)^    \]/m, 1].lines.map(&:strip)

    assert_equal '.withDirectory("/src", dependencies)', steps[0]
    assert_match(/\A\.withExec\(\["sh", "-c", "bundle install \|\| /, steps[1])
    assert_match(%r{\A\.withDirectory\("/src", source, }, steps[2])
    assert_equal(%w[Gemfile Gemfile.lock dagger.gemfile sdk/dagger-sdk.gemspec clients/core/dagger-clients-core.gemspec]
                   .map { %("#{it}",) }, files)
    assert_includes build.to_dang, "files.withNewFile(path, source.file(path).contents)"
  end

  def test_a_missing_dependency_file_is_left_for_bundler_to_name
    assert_includes build.to_dang, "if (source.exists(path)) {"
  end

  def test_a_failed_install_at_call_time_keeps_bundlers_error_and_hints_at_generation
    assert_includes build.to_dang, "bundle install || { status=$?; echo 'ruby-sdk: if you changed declarations, " \
                                   "clients or gems, run `dagger generate`' >&2; exit $status; }"
    api = build.installed(Dagger::QueryBuilder.new, Dagger::Type.new(Dagger::QueryBuilder.new.select("directory")))

    assert_equal %w[bundle install], api.selections.find { it.name == "withExec" }.args[:args]
  end

  def context_build
    Dagger::Mod::Build.new(image: "ruby:4.0", module_name: "my-module", gemspecs: GEMSPECS,
                           outside: ["../../gems/shared", "../tool"], module_path: "apps/web/my-module")
  end

  # Path gems outside the module make it build from its context directory,
  # where the module sits at a subpath beside them.
  def test_a_module_with_path_gems_outside_builds_from_its_context
    dang = context_build.to_dang

    assert_includes dang, "new(source: Directory!, subpath: String!, moduleName: String!) {"
    assert_includes dang, 'let anchor = subpath.trimSuffix("web/my-module")'
    assert_includes dang, %(      "gems/shared",\n      "web/tool",\n    ].reduce(dependencies) { files, path =>)
    assert_includes dang, '.withEnvVariable("BUNDLE_GEMFILE", "/src/" + subpath + "/Gemfile")'
    assert_includes dang, '.withWorkdir("/src/" + subpath)'
    assert_includes dang, '.withDirectory("/src", source, exclude: ["**/.bundle", "**/vendor/bundle"])'
    assert_includes dang, 'copied.withNewFile(anchor + path + "/" + file, source.directory(anchor + path)'
    refute_predicate build, :context?
  end

  def context_api
    source = Dagger::Type.new(Dagger::QueryBuilder.new.select("directory"))
    context_build.installed(Dagger::QueryBuilder.new, source, subpath: "x/apps/web/my-module")
  end

  def test_the_context_build_installs_the_outside_gems_whole_before_the_source
    dependencies = context_api.selections.find { it.name == "withDirectory" }.args[:source].query.selections
    files = %w[Gemfile Gemfile.lock dagger.gemfile] + GEMSPECS
    paths = dependencies.drop(1).map { it.args[:path] }

    assert_equal files.map { "x/apps/web/my-module/#{it}" } + %w[x/apps/gems/shared x/apps/web/tool], paths
    assert_equal "/src/x/apps/web/my-module", context_api.selections.find { it.name == "withWorkdir" }.args[:path]
  end

  def test_both_context_renderings_take_the_same_steps
    dang = context_build.to_dang[/^    container\n(.*?)^  }/m, 1].scan(/^\s+\.(\w+)\(/).flatten

    assert_equal dang, context_api.selections.map(&:name).drop(1)
  end

  # The API build and the rendered one must take the same steps.
  def test_both_renderings_take_the_same_steps
    source = Dagger::Type.new(Dagger::QueryBuilder.new.select("directory"))
    api = build.installed(Dagger::QueryBuilder.new, source).selections.map(&:name).drop(1)
    dang = build.to_dang[/^    container\n(.*?)^  }/m, 1].scan(/^\s+\.(\w+)\(/).flatten

    assert_equal dang, api
  end
end
