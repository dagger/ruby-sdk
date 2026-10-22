class E2E
  TYPES = "#{FIXTURES}/types".freeze
  TEXT = "she said \"hi\" \\ to C:\\temp\nand left: ünïcødé ✓".freeze

  function "Every row of the type mapping through dagger call: strings that need quoting, lists, nested " \
           "lists as arguments, optionals, enums, module objects as arguments, results and state, interfaces, core " \
           "objects and scalars in and out, void, defaults and ignore.", check: true
  #: (ws: Core::Workspace) -> void
  def types_round_trip_check(ws:)
    ground = playground(ws).with_new_file(path: "#{PLAYGROUND}/five.txt", contents: "12345")
    build = core.version
    # Void prints nothing, even as JSON.
    call = lambda do |*args|
      out = cli(ground, "-m", TYPES, "call", "--json", "--build", build, *args).stdout
      out.strip.empty? ? nil : JSON.parse(out)
    end
    {
      ["echo", "--text", TEXT] => TEXT,
      ["succ", "--number", "41"] => 42,
      ["half", "--number", "1.5"] => 0.75,
      ["negate", "--flag=true"] => false,
      ["nothing"] => nil,
      ["maybe", "--text", TEXT] => TEXT,
      ["maybe"] => nil,
      ["reversed", "--items", "a,b,c"] => %w[c b a],
      ["next-mood"] => "GRUMPY",
      ["next-mood", "--mood", "GRUMPY"] => "HAPPY",
      ["pair", "--left", "a", "--right", "b", "left"] => "a",
      ["pair", "--left", "a", "--right", "b", "swapped", "left"] => "b",
      ["pair", "--left", "a", "--right", "b", "--mood", "GRUMPY", "swapped", "mood"] => "GRUMPY",
      ["pair", "--left", "a", "--right", "b", "swapped", "secret"] => "kept",
      ["size", "--file", "five.txt"] => 5,
      ["write", "--contents", TEXT, "contents"] => TEXT,
      ["other-protocol", "--protocol", "TCP"] => "UDP",
      ["greeter", "greeting", "--name", build] => "hello, #{build}",
      ["defaults"] => "world 2 0.5",
      ["defaults", "--name", "x", "--times", "3", "--ratio", "1.25", "--loud"] => "X 3 1.25"
    }.each do |args, want|
      got = call.call(*args)
      check(got == want, "#{args.join(" ")}: got #{got.inspect}, want #{want.inspect}")
    end

    echoed = call.call("json", "--value", '{"a":[1,"x"]}')
    echoed = JSON.parse(echoed) if echoed.is_a?(String)
    check(echoed == { "echo" => { "a" => [1, "x"] } }, "a JSON scalar did not round-trip: #{echoed.inspect}")
    entries = call.call("entries", "--dir", TYPES)
    check(entries.include?("Gemfile") && !entries.intersect?(%w[lib/ sdk/ clients/]),
          "ignore gave #{entries.inspect}")
    read = cli(ground, "-m", TYPES, "-c", "read $(badge --text #{build})").stdout.strip
    check(read == "#{build}/noted", "a module object as an argument gave #{read.inspect}")
    through = cli(ground, "-m", TYPES, "-c", "greet-with $(greeter) --name #{build}").stdout.strip
    check(through == "through the interface: hello, #{build}", "an interface as an argument gave #{through.inspect}")
    lists(build)
    nullable_object
  end

  private

  # The CLI cannot pass a nested list and prints a list of objects as
  # references, so these rows go through GraphQL, to the module served into
  # this session. A nested list as a result comes back from the engine as
  # IDs, so only the argument direction is checked.
  # A nullable object field of a generated client is nil when the API
  # answers null, and an object to chain on otherwise.
  def nullable_object
    scalar = core.type_def.with_kind(kind: Core::TypeDefKind::STRING_KIND).as_object
    check(scalar.nil?, "a null object result came back as #{scalar.inspect}")
    object = core.type_def.with_object(name: "Pair").as_object
    check(object.is_a?(Core::ObjectTypeDef) && object.name.end_with?("Pair"),
          "an object result came back as #{object.inspect}")
  end

  def lists(build)
    Dagger::QueryBuilder.new.select("serveModule", address: "/#{TYPES}").execute(allow_nil: true)
    types = Dagger::QueryBuilder.new.select("types", build:)
    flat = types.select("flatten", rows: [[1, 2], [], [3]]).execute
    check(flat == [1, 2, 3], "a nested list argument arrived as #{flat.inspect}")
    pairs = types.select("pairs", names: %w[a b c]).select("right").execute
    check(pairs == [{ "right" => "b" }, { "right" => "c" }], "a list of module objects came back as #{pairs.inspect}")
    greetings = types.select("greeters").select("greeting", name: build).execute
    check(greetings == [{ "greeting" => "hello, #{build}" }] * 2,
          "a list of interfaces came back as #{greetings.inspect}")
  end

  public

  function "A function that raises fails the call, and the output names the error; an ExecError from the API " \
           "keeps its exit code and stderr.", check: true
  #: (ws: Core::Workspace) -> void
  def error_check(ws:)
    ground = playground(ws)
    build = core.version
    failed = cli_failure(ground, "-m", TYPES, "call", "--build", build, "explode", "--message", "boom #{build}")
    check(failed.include?("ArgumentError") && failed.include?("boom #{build}"),
          "the failed call does not name the error: #{failed}")
    rescued = JSON.parse(cli(ground, "-m", TYPES, "call", "--json", "--build", build, "exec-error").stdout)
    check(rescued == "exit=3 stderr=oops", "the ExecError lost its exit code or stderr: #{rescued.inspect}")
  end
end
