require_relative "mod_helper"
require "stringio"
require "tmpdir"

class ErrorReportTest < Minitest::Test
  ORIGIN = "[traceparent:#{"a" * 32}-#{"b" * 16}]".freeze
  SDK_FRAMES = ["/src/sdk/lib/dagger/mod/dispatch.rb:56:in 'Kernel#public_send'",
                "sdk/exe/dagger-mod:7:in '<main>'"].freeze
  EXTENSIONS = { "_type" => "EXEC_ERROR", "cmd" => %w[sh -c false], "exitCode" => 1, "stdout" => "out",
                 "stderr" => "oops" }.freeze
  FRAMEWORK = ["/src/sdk/", "/src/clients/", "/usr/local/bundle/", "/usr/local/lib/ruby/"].freeze

  def test_an_error_of_the_module_goes_to_the_file_and_its_logs_get_its_own_frames
    error = raised(RuntimeError.new("boom"), "/src/lib/main.rb:3:in 'Main#fail'", *SDK_FRAMES,
                   "/usr/local/bundle/gems/x-1/lib/x.rb:1:in 'X.y'", "/src/lib/main/helper.rb:9:in 'Helper.go'")
    file, logs = report_to_file(error)

    assert_equal({ "message" => "boom", "values" => {} }, JSON.parse(file))
    assert_equal "/src/lib/main.rb:3:in 'Main#fail': boom (RuntimeError)\n" \
                 "\tfrom /src/lib/main/helper.rb:9:in 'Helper.go'\n", logs
  end

  # The engine shows an API error that names its origin with the logs of the
  # call that failed; the report keeps the origin and the error's values.
  def test_an_api_error_that_names_its_origin_logs_nothing
    file, logs = report_to_file(raised(exec_error, "/src/sdk/lib/dagger/connection.rb:87:in 'read'",
                                       "/src/lib/main.rb:5:in 'Main#run'"))

    assert_equal({ "message" => "exit code: 1 #{ORIGIN}", "values" => EXTENSIONS }, JSON.parse(file))
    assert_empty logs
  end

  # Ruby makes the error being rescued the cause of one raised in its rescue.
  def test_a_wrapped_api_error_logs_both_without_origins_and_reports_the_api_errors_values
    error = wrap(exec_error) { raise "ran a failing command: #{it.message}" }
    file, logs = report_to_file(error)
    report = JSON.parse(file)

    assert_equal "ran a failing command: exit code: 1 #{ORIGIN}", report["message"]
    assert_equal EXTENSIONS, report["values"]
    assert_match(/\A\S+error_report_test\.rb:\d+:in .*: ran a failing command: exit code: 1 \(RuntimeError\)\n/, logs)
    assert_match(/^\S+error_report_test\.rb:\d+:in .*: exit code: 1 \(Dagger::ExecError\)\n/, logs)
    refute_includes logs, "traceparent"
  end

  def test_an_error_of_the_sdk_logs_only_the_hint
    file, logs = report_to_file(raised(Dagger::Mod::InvalidInputError.new("Main has no function nope"), *SDK_FRAMES),
                                hint: "dagger-mod: run `dagger generate`")

    assert_equal "Main has no function nope", JSON.parse(file)["message"]
    assert_equal "dagger-mod: run `dagger generate`\n", logs
  end

  # Without a frame of the module's, an error is its message and class alone;
  # a SyntaxError's, without syntax_suggest's guess, and its report the first
  # line, which names the file and the line.
  def test_a_module_file_that_does_not_parse
    error = syntax_error("class Main\nend\n\nthis is not ruby)\n")
    file, logs = report_to_file(raised(error, "/usr/local/lib/ruby/4.0.0/bundled_gems.rb:60:in 'Kernel.require'",
                                       *SDK_FRAMES))
    path = error.path

    assert_equal "#{path}:4: syntax errors found", JSON.parse(file)["message"]
    assert_match(/\A#{Regexp.escape(path)}:4: syntax errors found \(SyntaxError\)\n.*> 4 \| this is not ruby\)\n/m,
                 logs)
    refute_includes logs, "-->"
    assert logs.end_with?("expecting end-of-input\n"), logs
  end

  def test_an_error_without_a_message_reports_its_class
    file, = report_to_file(raised(RuntimeError.new(""), "/src/lib/main.rb:3:in 'Main#fail'"))

    assert_equal "RuntimeError", JSON.parse(file)["message"]
  end

  # An engine that names no file: the error as Ruby prints it, then the
  # marker line the entrypoint reads, last, its message with the origin.
  def test_without_a_file_the_error_goes_to_stderr_with_the_marker
    logs = report(raised(RuntimeError.new("boom #{ORIGIN}"), "/src/lib/main.rb:3:in 'Main#fail'", *SDK_FRAMES),
                  path: nil, hint: "dagger-mod: hint")
    lines = logs.lines(chomp: true)

    assert_equal "/src/lib/main.rb:3:in 'Main#fail': boom (RuntimeError)", lines.first
    assert_includes logs, "\tfrom sdk/exe/dagger-mod:7:in '<main>'\n"
    assert_equal ["dagger-mod: hint", %(::dagger-function-error::"boom #{ORIGIN}")], lines.last(2)
  end

  def test_without_a_file_an_api_error_shows_its_message_and_stderr
    lines = report(raised(exec_error, *SDK_FRAMES), path: nil).lines(chomp: true)

    assert_equal ["dagger-mod: Dagger::ExecError: exit code: 1", "oops",
                  %(::dagger-function-error::"exit code: 1 #{ORIGIN}")], lines
  end

  def test_a_file_that_cannot_be_written_falls_back_to_the_marker
    logs = report(raised(RuntimeError.new("boom"), "/src/lib/main.rb:3:in 'Main#fail'"),
                  path: "/nonexistent/dir/error.json")

    assert logs.end_with?(%(::dagger-function-error::"boom"\n)), logs
  end

  def test_the_marker_message_is_cut_and_keeps_its_origins
    long = "x" * (Dagger::Mod::ErrorReport::MARKER_LIMIT * 2)
    marker = report(raised(RuntimeError.new("#{long} #{ORIGIN}"), "/src/lib/main.rb:3:in 'Main#fail'"),
                    path: nil).lines.last
    message = JSON.parse(marker.delete_prefix(Dagger::Mod::ErrorReport::MARKER))

    assert_equal "#{"x" * Dagger::Mod::ErrorReport::MARKER_LIMIT}... #{ORIGIN}", message
  end

  def test_a_report_over_the_limit_is_shortened_to_fit
    big = "y" * Dagger::Mod::ErrorReport::FILE_LIMIT
    error = Dagger::ExecError.new([{ "message" => "#{big} #{ORIGIN}", "extensions" => { "stderr" => "#{big}end" } }],
                                  "query")
    report = Dagger::Mod::ErrorReport.file_report(error)
    decoded = JSON.parse(report)

    assert_operator report.bytesize, :<=, Dagger::Mod::ErrorReport::FILE_LIMIT
    assert decoded["message"].end_with?("... #{ORIGIN}"), decoded["message"][-80..]
    assert decoded["values"]["stderr"].start_with?("...") && decoded["values"]["stderr"].end_with?("yend")
  end

  def test_invalid_utf8_is_reported
    file, = report_to_file(raised(RuntimeError.new("bad \xff byte".b), "/src/lib/main.rb:3:in 'Main#fail'"))

    assert_equal "bad \uFFFD byte", JSON.parse(file)["message"]
  end

  def test_the_framework_is_the_sdk_the_clients_the_gems_and_ruby
    report = Dagger::Mod::ErrorReport.for_module(module_root: "/src", sdk_root: "/src/sdk", env: {})
    framework = report.instance_variable_get(:@framework)

    assert_includes framework, "/src/sdk/"
    assert_includes framework, "/src/clients/"
    assert_includes framework, "#{RbConfig::CONFIG["rubylibprefix"]}/"
    refute report.shows_trace?(exec_error)
    assert report.shows_trace?(RuntimeError.new("boom"))
  end

  private

  def exec_error
    Dagger::ExecError.new([{ "message" => "exit code: 1 #{ORIGIN}", "extensions" => EXTENSIONS.dup }], "query")
  end

  def raised(error, *frames)
    error.set_backtrace(frames)
    error
  end

  def wrap(inner)
    raise inner
  rescue Dagger::QueryError => e
    begin
      yield e
    rescue StandardError => wrapped
      wrapped
    end
  end

  def syntax_error(source)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "main.rb")
      File.write(path, source)
      load path
    end
    flunk "the source parsed"
  rescue SyntaxError => e
    e
  end

  def reporter(path)
    Dagger::Mod::ErrorReport.new(framework: FRAMEWORK, cwd: "/src", path:, stderr: (@stderr = StringIO.new))
  end

  def report(error, path:, hint: nil)
    reporter(path).report(error, hint:)
    @stderr.string
  end

  def report_to_file(error, hint: nil)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "error.json")
      logs = report(error, path:, hint:)
      [File.read(path), logs]
    end
  end
end
