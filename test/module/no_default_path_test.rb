require_relative "../test_helper"

# A contextual directory resolves against the caller's workspace, not the
# module that asks for it, so nothing the SDK writes or ships may ask for one.
class NoDefaultPathTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  # Core's bindings mirror the engine's API, whose Function.withArg takes the
  # option; the recorded schema and the designs describe it.
  EXEMPT = %r{(\A|/)clients/core/|\Atest/fixtures/core-schema\.json\z|\Ahack/designs/|\Atmp/|vendor/bundle/}
  PATTERN = /default_path|defaultPath/

  # Other hidden directories at the root hold the state of tools, not the
  # repository's files.
  def test_no_source_or_generated_file_asks_for_a_contextual_directory
    offenders = Dir.glob(["**/*", ".dagger/**/*"], base: ROOT).select do |path|
      next false if path.match?(EXEMPT) || path == "test/module/no_default_path_test.rb"

      full = File.join(ROOT, path)
      File.file?(full) && File.binread(full).match?(PATTERN)
    end

    assert_empty offenders
  end
end
