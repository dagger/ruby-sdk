require_relative "mod_helper"
require "json"
require "fileutils"
require "open3"
require "tmpdir"

class DispatchTest < Minitest::Test
  include ModHelper

  MODULE = <<~RUBY.freeze
    class Mood < Dagger::Mod::Enum
      member :HAPPY, "happy"
      member :GRUMPY, "grumpy"
    end

    class Note
      extend Dagger::Mod::Object

      field :text #: String
    end

    class Main
      extend Dagger::Mod::Object

      field :greeting, default: "hello" #: String
      field :calls, default: 0 #: Integer
      field :source, private: true #: ModHelper::Core::Directory

      def initialize(**)
        super
        raise "initialize ran" if greeting == "never"
      end

      function
      #: (?name: String, ?mood: Mood) -> String
      def greet(name: "world", mood: Mood::HAPPY) = "\#{greeting}, \#{name} (\#{mood.value})"

      function
      #: (notes: Array[Note], limit: Integer?) -> Array[Note]
      def keep(notes:, limit:) = limit ? notes.first(limit) : notes

      function
      #: (dir: ModHelper::Core::Directory) -> String
      def node_type(dir:) = dir.query.selections.first.inline_type

      function
      #: () -> Mood
      def mood = Mood::GRUMPY

      function
      #: () -> Main
      def again = Main.new(greeting: greeting * 2, calls: calls + 1, source:)

      function
      #: () -> Main
      def copy = dup

      function
      #: (?stamp: String) -> String
      def stamp(stamp: "\#{greeting}!") = stamp

      function
      #: () -> void
      def fail = raise(ArgumentError, "boom")

      function
      #: () -> String
      def wrong = 42
    end
  RUBY

  def setup
    super
    declare(MODULE)
    annotate
  end

  def dispatch(fn_name, receiver: nil, **args)
    Dagger::Mod::Dispatch.new(Dagger::Mod.registry).call(
      "receiverType" => "Main", "receiverValue" => receiver && JSON.generate(receiver), "fnName" => fn_name,
      "fnArgs" => JSON.generate(args)
    )
  end

  def state = { "greeting" => "hi", "calls" => 1, "source" => "dir-id" }

  def test_a_constructor_call_takes_the_fields_and_returns_the_state
    result = dispatch("", greeting: "hey", source: "dir-id")

    assert_equal({ "greeting" => "hey", "calls" => 0, "source" => "dir-id" }, result)
  end

  def test_a_call_holds_the_module_source_its_request_names
    $LOAD_PATH.unshift File.expand_path("../../clients/core/lib", __dir__)
    request = { "receiverType" => "Main", "receiverValue" => nil, "fnName" => "", "fnArgs" => '{"source":"d"}',
                "moduleSource" => "src-id" }
    Dagger::Mod::Dispatch.new(Dagger::Mod.registry).call(request)
    source = Dagger::Mod.module_source

    assert_instance_of Dagger::Clients::Core::Directory, source
    assert_equal "src-id", source.query.loaded_id
  ensure
    Dagger::Mod.module_source_id = nil
  end

  def test_there_is_no_module_source_outside_a_call
    assert_raises(Dagger::Mod::Error) { Dagger::Mod.module_source }
  end

  def test_a_null_receiver_is_an_empty_state_for_a_constructor
    request = { "receiverType" => "Main", "receiverValue" => nil, "fnName" => "", "fnArgs" => '{"source":"d"}' }
    result = Dagger::Mod::Dispatch.new(Dagger::Mod.registry).call(request)

    assert_equal "hello", result["greeting"]
  end

  def test_a_function_runs_on_a_receiver_rebuilt_without_initialize
    assert_equal "never, you (grumpy)", dispatch("greet", receiver: state.merge("greeting" => "never"),
                                                          name: "you", mood: "GRUMPY")
  end

  def test_an_omitted_argument_gets_its_declared_default
    assert_equal "hi, world (happy)", dispatch("greet", receiver: state)
  end

  def test_an_optional_argument_left_out_or_null_keeps_the_default_of_the_def
    stamps = [dispatch("stamp", receiver: state), dispatch("stamp", receiver: state, stamp: nil),
              dispatch("stamp", receiver: state, stamp: "x")]

    assert_equal ["hi!", "hi!", "x"], stamps
  end

  def test_json_text_is_decoded_once
    assert_equal 'hi, {"a":1} (happy)', dispatch("greet", receiver: state, name: '{"a":1}')
  end

  def test_lists_optionals_module_objects_and_enums_round_trip
    notes = [{ "text" => "a" }, { "text" => "b" }]

    assert_equal [{ "text" => "a" }], dispatch("keep", receiver: state, notes:, limit: 1)
    assert_equal notes, dispatch("keep", receiver: state, notes:, limit: nil)
    assert_equal "GRUMPY", dispatch("mood", receiver: state)
    assert_equal({ "greeting" => "hihi", "calls" => 2, "source" => "dir-id" }, dispatch("again", receiver: state))
  end

  # The engine's collection base comes with the receiver and goes back with
  # a copy of it, never with a new object.
  def test_a_collection_base_in_the_state_goes_back_with_a_copy_only
    based = state.merge("__daggerCollectionBase" => "base-id")

    assert_equal "base-id", dispatch("copy", receiver: based)["__daggerCollectionBase"]
    refute dispatch("again", receiver: based).key?("__daggerCollectionBase")
    refute dispatch("copy", receiver: state).key?("__daggerCollectionBase")
  end

  def test_a_core_object_arrives_by_id_and_is_loaded_with_node
    assert_equal "Directory", dispatch("nodeType", receiver: state, dir: "some-id")
  end

  def test_errors
    assert_raises(Dagger::Mod::FunctionError) { dispatch("fail", receiver: state) }
    assert_raises(Dagger::Mod::InvalidResultError) { dispatch("wrong", receiver: state) }
    assert_raises(Dagger::Mod::InvalidInputError) { dispatch("greet", receiver: state, mood: "SAD") }
    assert_raises(Dagger::Mod::InvalidInputError) { dispatch("nope", receiver: state) }
    assert_raises(Dagger::Mod::InvalidInputError) { dispatch("greet", receiver: state, name: 3) }
  end

  def test_the_cli_writes_a_result_or_exits_2_without_one
    Dir.mktmpdir do |dir|
      write_module(dir)
      ok, ok_status = run_cli(dir, "greet", '{"name":"cli"}')
      failed, failed_status = run_cli(dir, "fail", "{}")

      assert_equal [0, '"hi, cli (happy)"'], [ok_status.exitstatus, File.read(File.join(dir, "ok.json"))], ok
      assert_equal 2, failed_status.exitstatus
      assert_match(/FunctionError: .*boom/, failed)
      refute_path_exists File.join(dir, "fail.json")
    end
  end

  def test_a_call_the_module_no_longer_matches_shows_its_error_and_the_hint
    Dir.mktmpdir do |dir|
      write_module(dir)
      renamed, renamed_status = run_cli(dir, "renamed", "{}")
      File.write(File.join(dir, "main.rb"), "require \"dagger/clients/gone\"\n")
      unloaded, unloaded_status = run_cli(dir, "greet", "{}")

      assert_equal 2, renamed_status.exitstatus
      assert_match(/InvalidInputError: Main has no function renamed\n.*run `dagger generate`/, renamed)
      assert_equal 1, unloaded_status.exitstatus
      assert_match(%r{cannot load such file -- dagger/clients/gone.*\(LoadError\).*run `dagger generate`}m, unloaded)
    end
  end

  def test_a_call_without_signatures_asks_for_dagger_generate
    Dir.mktmpdir do |dir|
      write_module(dir)
      File.delete(File.join(dir, Dagger::Mod::Signatures::FILE))
      out, status = run_cli(dir, "greet", "{}")

      assert_equal 2, status.exitstatus
      assert_match(%r{sdk/entrypoint/signatures.json is missing: run `dagger generate`}, out)
    end
  end

  private

  # The module as a file, and its signatures as generation writes them.
  def write_module(dir)
    source = "require \"dagger\"\nmodule ModHelper; module Core; class Directory < Dagger::Type; end; end; end\n" \
             "#{MODULE}"
    File.write(File.join(dir, "main.rb"), source)
    FileUtils.mkdir_p(File.join(dir, "sdk/entrypoint"))
    File.write(File.join(dir, Dagger::Mod::Signatures::FILE),
               JSON.generate(RubySdk::Signatures.parse("main.rb" => source)))
  end

  def run_cli(dir, fn_name, args)
    request = JSON.generate("receiverType" => "Main", "receiverValue" => JSON.generate(state), "fnName" => fn_name,
                            "fnArgs" => args)
    output = File.join(dir, fn_name == "fail" ? "fail.json" : "ok.json")
    sdk = File.expand_path("../../sdk", __dir__)
    Open3.capture2e({ "DAGGER_MODULE" => "main", "DAGGER_MODULE_FILE" => "main.rb" },
                    "ruby", "-I", "#{sdk}/lib", "#{sdk}/exe/dagger-mod", "call", "--output", output,
                    stdin_data: request, chdir: dir)
  end
end
