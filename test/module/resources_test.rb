require_relative "../test_helper"
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ruby_sdk/resources"

class ResourcesTest < Minitest::Test
  # Files by their path relative to the module's directory, which sits
  # three directories below the workspace's root.
  def resources(files, depth: 3) = RubySdk::Resources.new(files.method(:[]).to_proc, depth)

  def refusal(gemfile, **)
    assert_raises(RubySdk::Error) { resources({ "Gemfile" => gemfile }, **).found }.message
  end

  def test_path_gems_gemspecs_and_evaluated_files_outside_the_module_are_found
    gemfile = <<~RUBY
      source "https://rubygems.org"

      eval_gemfile "dagger.gemfile"
      eval_gemfile "../../common/Gemfile.shared"
      gem "shared", path: "../../../gems/shared"
      gem "inside", path: "vendor/inside"
      gem "remote", git: "https://example.com/remote.git"
      gemspec path: "../tool"
      ruby file: "../../../.ruby-version"
      group :test do
        path "../../../gems" do
          gem "helper"
        end
      end
    RUBY
    shared = %(gem "deep", path: "../deep"\n)
    found = resources({ "Gemfile" => gemfile, "dagger.gemfile" => %(gem "dagger-sdk", path: "sdk"\n),
                        "../../common/Gemfile.shared" => shared }).found
    described = found.map { [it.path, it.directory, it.at] }

    assert_equal [["../../../.ruby-version", false, "Gemfile:9"], ["../../../gems", true, "Gemfile:11"],
                  ["../../../gems/shared", true, "Gemfile:5"], ["../../common/Gemfile.shared", false, "Gemfile:4"],
                  ["../../deep", true, "../../common/Gemfile.shared:1"], ["../tool", true, "Gemfile:8"]], described
  end

  def test_the_patterns_list_directories_whole_but_for_bundlers_own_then_files
    gemfile = %(gem "a", path: "../../a"\ngem "b", path: "../../a/b"\neval_gemfile "../../a/Gemfile.x"\n) +
              %(ruby file: "../.ruby-version"\n)

    assert_equal ["../../a", "../.ruby-version", "!../../a/.bundle", "!../../a/vendor/bundle"],
                 resources({ "Gemfile" => gemfile }).patterns
  end

  def test_a_module_without_a_gemfile_or_anything_outside_has_no_resources
    assert_empty resources({}).patterns
    assert_empty resources({ "Gemfile" => %(gem "a", path: "lib/a"\neval_gemfile "dagger.gemfile"\n) }).patterns
  end

  def test_refusals_name_the_file_and_line
    assert_equal "Gemfile:2: path: is not a string literal; generation reads it to load what the module needs " \
                 "outside its directory, so write the path itself",
                 refusal(%(x = "../a"\ngem "a", path: x\n))
    assert_equal "Gemfile:1: path: is not a string literal; generation reads it to load what the module needs " \
                 "outside its directory, so write the path itself",
                 refusal(%(gem "a", path: "../\#{name}"\n))
    assert_equal 'Gemfile:1: "/opt/a" is absolute; name what the module needs outside its directory by a path ' \
                 "relative to the file that names it", refusal(%(gem "a", path: "/opt/a"\n))
    assert_equal 'Gemfile:1: "../../../../a" leaves the workspace\'s root, which holds every file the engine loads ' \
                 "with the module", refusal(%(gem "a", path: "../../../../a"\n))
    assert_equal 'Gemfile:1: ".." holds the module itself; name the directory of what it needs',
                 refusal(%(gemspec path: ".."\n))
  end

  def test_paths_are_cleaned_lexically
    assert_equal "../b", RubySdk::Resources.clean("./a/../../b/")
    assert_equal ".", RubySdk::Resources.clean("a/..")
    assert RubySdk::Resources.outside?("../x")
    refute RubySdk::Resources.outside?("x/../y")
  end
end
