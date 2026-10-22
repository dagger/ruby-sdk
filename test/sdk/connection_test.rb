require_relative "../test_helper"
require "dagger"

class ConnectionTest < Minitest::Test
  def with_engine(*replies)
    engine = FakeEngine.new(replies)
    connection = Dagger::Connection.new(port: engine.port, token: "secret")
    yield engine, connection
  ensure
    connection&.close
    engine&.close
  end

  def test_a_query_posts_json_with_the_session_token
    with_engine(FakeEngine.data("version" => "v1")) do |engine, connection|
      assert_equal({ "version" => "v1" }, connection.execute("query { version }"))
      request = engine.requests.first

      assert_equal "/query", request.path
      assert_equal "query { version }", request.query
      assert_equal "Basic #{["secret:"].pack("m0")}", request.headers["authorization"]
      assert_equal "application/json", request.headers["content-type"]
    end
  end

  def test_a_traceparent_in_the_environment_goes_with_the_request
    traceparent = "00-0123456789abcdef0123456789abcdef-0123456789abcdef-01"
    with_env("TRACEPARENT" => traceparent) do
      with_engine(FakeEngine.data({})) do |engine, connection|
        connection.execute("query { version }")

        assert_equal traceparent, engine.requests.first.headers["traceparent"]
      end
    end
  end

  def test_a_malformed_traceparent_is_not_sent
    with_env("TRACEPARENT" => "00-xyz") do
      with_engine(FakeEngine.data({})) do |engine, connection|
        connection.execute("query { version }")

        refute engine.requests.first.headers.key?("traceparent")
      end
    end
  end

  def test_no_read_timeout_by_default
    with_engine(FakeEngine.data({})) do |_engine, connection|
      connection.execute("query { version }")

      assert_nil connection.send(:client).read_timeout
    end
  end

  def test_a_dropped_connection_is_retried
    with_engine(:drop, :drop, FakeEngine.data("version" => "v1")) do |engine, connection|
      assert_equal({ "version" => "v1" }, connection.execute("query { version }"))
      assert_equal 3, engine.requests.size
    end
  end

  def test_retries_stop_after_five_attempts
    with_engine(*[:drop] * 5) do |engine, connection|
      error = assert_raises(Dagger::TransportError) { connection.execute("query { version }") }

      assert_match(/Failed to execute request/, error.message)
      assert_equal 5, engine.requests.size
    end
  end

  def test_graphql_errors_raise_a_query_error
    error = { "message" => "boom", "path" => ["container"], "locations" => [{ "line" => 2, "column" => 3 }] }
    with_engine(FakeEngine.errors(error)) do |_engine, connection|
      raised = assert_raises(Dagger::QueryError) { connection.execute("query {\n  container\n}") }

      assert_equal "boom", raised.message
      assert_equal ["container"], raised.path
      assert_equal "query {\n  container\n}", raised.query
      assert_equal "1: query {\n2:   container\n     ^\n3: }", raised.debug_query
    end
  end

  def test_an_exec_error_carries_its_command_and_output
    error = {
      "message" => "process exited with 3",
      "extensions" => {
        "_type" => "EXEC_ERROR", "cmd" => %w[sh -c false], "exitCode" => 3, "stdout" => "out", "stderr" => "err"
      }
    }
    with_engine(FakeEngine.errors(error)) do |_engine, connection|
      raised = assert_raises(Dagger::ExecError) { connection.execute("query { x }") }

      assert_kind_of Dagger::QueryError, raised
      assert_equal %w[sh -c false], raised.command
      assert_equal 3, raised.exit_code
      assert_equal "out", raised.stdout
      assert_equal "err", raised.stderr
      assert_equal "process exited with 3", raised.message
    end
  end

  def test_a_body_that_is_not_json_is_a_transport_error
    with_engine({ status: 502, body: "bad gateway" }) do |_engine, connection|
      error = assert_raises(Dagger::TransportError) { connection.execute("query { version }") }

      assert_equal "Unexpected response from engine: 502 bad gateway", error.message
    end
  end

  def test_a_non_ok_status_without_errors_is_a_transport_error
    with_engine({ status: 500, body: "{}" }) do |_engine, connection|
      assert_raises(Dagger::TransportError) { connection.execute("query { version }") }
    end
  end

  def test_malformed_errors_are_a_transport_error
    with_engine({ status: 200, body: JSON.generate(errors: ["nope"]) }) do |_engine, connection|
      error = assert_raises(Dagger::TransportError) { connection.execute("query { version }") }

      assert_match(/Unexpected error response/, error.message)
    end
  end

  def test_the_environment_gives_the_connection
    with_env("DAGGER_SESSION_PORT" => "1234", "DAGGER_SESSION_TOKEN" => "t") do
      assert_equal 1234, Dagger::Connection.from_env.port
    end
    with_env("DAGGER_SESSION_PORT" => nil, "DAGGER_SESSION_TOKEN" => nil) do
      assert_nil Dagger::Connection.from_env
    end
  end

  def test_a_port_without_a_token_or_a_bad_port_is_refused
    with_env("DAGGER_SESSION_PORT" => "1234", "DAGGER_SESSION_TOKEN" => nil) do
      assert_raises(Dagger::ConnectionError) { Dagger::Connection.from_env }
    end
    with_env("DAGGER_SESSION_PORT" => "x", "DAGGER_SESSION_TOKEN" => "t") do
      assert_raises(Dagger::ConnectionError) { Dagger::Connection.from_env }
    end
  end

  private

  def with_env(values)
    saved = values.keys.to_h { [it, ENV.fetch(it, nil)] }
    values.each { |name, value| ENV[name] = value }
    yield
  ensure
    saved.each { |name, value| ENV[name] = value }
  end
end
