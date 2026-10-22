require_relative "../test_helper"
require "dagger"

class SessionTest < Minitest::Test
  def test_without_a_session_or_a_cli_there_is_none_to_connect_to
    saved = ENV.delete("DAGGER_SESSION_PORT")
    cli = ENV.fetch("_EXPERIMENTAL_DAGGER_CLI_BIN", nil)
    ENV["_EXPERIMENTAL_DAGGER_CLI_BIN"] = "/nonexistent/dagger"
    error = assert_raises(Dagger::ConnectionError) { Dagger::Session.new.execute("query { version }") }

    assert_match(%r{cannot start /nonexistent/dagger session}, error.message)
  ensure
    ENV["DAGGER_SESSION_PORT"] = saved if saved
    ENV["_EXPERIMENTAL_DAGGER_CLI_BIN"] = cli
  end

  def test_one_default_session_per_process
    assert_same Dagger.default_session, Dagger.default_session
  end

  def test_connect_yields_a_session_and_closes_it
    engine = FakeEngine.new([FakeEngine.data("version" => "v")])
    version = Dagger.connect(port: engine.port, token: "t") do |session|
      Dagger::QueryBuilder.new(session:).select("version").execute
    end

    assert_equal "v", version
  ensure
    engine&.close
  end

  def test_the_sdk_files_load_without_generated_code
    lib = File.expand_path("../../sdk/lib", __dir__)
    script = <<~RUBY
      Dir["#{lib}/**/*.rb"].each { require it }
      print $LOADED_FEATURES.grep(%r{/dagger/clients/}).inspect
    RUBY

    assert_equal "[]", IO.popen(["ruby", "-I", lib, "-e", script], &:read)
  end
end
