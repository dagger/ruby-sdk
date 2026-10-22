require_relative "../test_helper"
require "dagger"
require "open3"
require "tmpdir"

class ClientTest < Minitest::Test
  TARGET = Dagger::Client::Target.new(name: "lib", ref: "/.dagger/modules/lib")
  VALIDATION = { "message" => 'Cannot query field "nope" on type "Lib".',
                 "extensions" => { "code" => "GRAPHQL_VALIDATION_FAILED" } }.freeze

  def with_engine(*replies)
    engine = FakeEngine.new(replies)
    session = Dagger::Session.new(Dagger::Connection.new(port: engine.port, token: "t"))
    yield engine, session
  ensure
    session&.close
    engine&.close
  end

  def lib_query(session) = Dagger::Client.root(TARGET, "lib", {}, session:).select("greeting")

  def test_a_target_is_served_once_per_session_before_its_first_query
    with_engine(FakeEngine.data("serveModule" => nil), FakeEngine.data("lib" => { "greeting" => "hi" }),
                FakeEngine.data("lib" => { "greeting" => "hi" })) do |engine, session|
      2.times { assert_equal "hi", lib_query(session).execute }

      assert_equal(1, engine.requests.count { it.query.include?("serveModule") })
      assert_includes engine.requests.first.query, 'serveModule(address: "/.dagger/modules/lib")'
    end
  end

  def test_two_sessions_each_serve_the_target
    2.times do
      with_engine(FakeEngine.data("serveModule" => nil), FakeEngine.data("lib" => { "greeting" => "hi" })) do |e, s|
        lib_query(s).execute

        assert_equal(1, e.requests.count { it.query.include?("serveModule") })
      end
    end
  end

  def test_a_git_target_is_served_at_its_pin
    target = Dagger::Client::Target.new(name: "lib", ref: "github.com/acme/lib@v1", pin: "abc")
    with_engine(FakeEngine.data("serveModule" => nil), FakeEngine.data("lib" => { "x" => 1 })) do |engine, session|
      Dagger::Client.root(target, "lib", {}, session:).select("x").execute

      assert_includes engine.requests.first.query, 'serveModule(address: "github.com/acme/lib@v1", refPin: "abc")'
    end
  end

  def test_a_failed_load_is_a_client_load_error
    with_engine(FakeEngine.errors("message" => "no such module")) do |_engine, session|
      error = assert_raises(Dagger::ClientLoadError) { lib_query(session).execute }

      assert_equal TARGET, error.target
      assert_match(%r{Failed to load client "lib" from "/.dagger/modules/lib": no such module}, error.message)
    end
  end

  def test_a_session_holds_one_target_per_name
    other = Dagger::Client::Target.new(name: "lib", ref: "/elsewhere")
    with_engine(FakeEngine.data("serveModule" => nil), FakeEngine.data("lib" => { "greeting" => "hi" })) do |_e, s|
      lib_query(s).execute

      assert_raises(Dagger::ClientLoadError) { Dagger::Client.root(other, "lib", {}, session: s).execute }
    end
  end

  def test_a_validation_error_after_a_load_means_a_stale_client
    with_engine(FakeEngine.data("serveModule" => nil), FakeEngine.errors(VALIDATION)) do |_engine, session|
      error = assert_raises(Dagger::StaleClientError) { lib_query(session).execute }

      assert_match(%r{Cannot query field "nope".*The client "lib" from /.dagger/modules/lib is out of date},
                   error.message)
    end
  end

  def test_an_error_that_quotes_the_same_words_from_a_resolver_is_not_stale
    resolver = VALIDATION.merge("path" => ["lib"], "extensions" => {})
    with_engine(FakeEngine.data("serveModule" => nil), FakeEngine.errors(resolver)) do |_engine, session|
      error = assert_raises(Dagger::QueryError) { lib_query(session).execute }

      refute_kind_of Dagger::StaleClientError, error
    end
  end

  def test_a_client_for_another_core_is_refused_unless_types_are_registering
    assert_raises(Dagger::StaleClientError) { Dagger::Client.check_core("lib", "sha256:a", "sha256:b") }
    _out, err = capture_io { Dagger::Client.registering { Dagger::Client.check_core("lib", "sha256:a", "sha256:b") } }

    assert_match(/generated for core sha256:a, but the installed core is sha256:b/, err)
    assert_nil Dagger::Client.check_core("lib", "sha256:a", "sha256:a")
  end

  def test_neither_core_nor_the_client_roots_is_a_declared_client
    loaded = Gem.loaded_specs.dup
    Gem.loaded_specs.replace("dagger-sdk" => nil, "dagger-clients-core" => nil, "dagger-clients-roots" => nil)
    Dagger::Client.instance_variable_set(:@declared_targets, nil)

    assert_empty Dagger::Client.declared_targets
  ensure
    Gem.loaded_specs.replace(loaded)
    Dagger::Client.instance_variable_set(:@declared_targets, nil)
  end

  def test_a_contributed_field_adds_its_target_to_the_receiver
    receiver = Dagger::Type.new(Dagger::QueryBuilder.new.select("directory"))
    query = Dagger::Client.select(receiver, TARGET, "asLib", {})

    assert_equal [TARGET], query.targets
    assert_equal %w[directory asLib], query.selections.map(&:name)
  end

  # Each program runs in its own interpreter, with a fake CLI that prints
  # connection parameters and marks when its stdin closes.
  FAKE_CLI = <<~RUBY.freeze
    #!/usr/bin/env ruby
    File.write(File.join(ENV.fetch("MARKS"), "started"), ARGV.join(" "))
    puts '{"port": 4242, "session_token": "fake"}'
    $stdout.flush
    $stdin.read
    sleep 0.3
    File.write(File.join(ENV.fetch("MARKS"), "ended"), "ended")
  RUBY

  def run_program(program, env = {})
    Dir.mktmpdir do |marks|
      cli = File.join(marks, "dagger")
      File.write(cli, FAKE_CLI)
      File.chmod(0o755, cli)
      lib = File.expand_path("../../sdk/lib", __dir__)
      environment = { "_EXPERIMENTAL_DAGGER_CLI_BIN" => cli, "MARKS" => marks, "DAGGER_SESSION_PORT" => nil,
                      "DAGGER_SESSION_TOKEN" => nil }.merge(env)
      output, status = Open3.capture2e(environment, "ruby", "-I", lib, "-e", "require 'dagger'\n#{program}")
      yield output, status, marks
    end
  end

  def test_a_plain_program_provisions_a_session_and_ends_it_at_exit
    run_program("print Dagger.default_session.connection.port") do |output, status, marks|
      assert_predicate status, :success?, output
      assert_equal "4242", output
      assert_equal "session --label dagger.io/sdk.name:ruby", File.read(File.join(marks, "started"))
      assert_path_exists File.join(marks, "ended")
    end
  end

  def test_a_session_in_the_environment_is_never_provisioned
    program = "print Dagger.default_session.connection.port"
    run_program(program, "DAGGER_SESSION_PORT" => "5151", "DAGGER_SESSION_TOKEN" => "t") do |output, status, marks|
      assert_equal [true, "5151"], [status.success?, output]
      refute_path_exists File.join(marks, "started")
    end
  end

  def test_a_module_runtime_never_provisions
    program = <<~RUBY
      Dagger.mark_module_runtime!
      begin
        Dagger.default_session.connection
      rescue Dagger::ConnectionError
        print "refused"
      end
    RUBY
    run_program(program) do |output, _status, marks|
      assert_equal "refused", output
      refute_path_exists File.join(marks, "started")
    end
  end
end
