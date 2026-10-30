class E2E
  CONTAINER_ANNOTATION = "#: () -> Dagger::Clients::Core::Container".freeze
  BAD_FUNCTION = %(function "Bad."\n#: (name: String) -> String\ndef bad(nam:) = nam\n).freeze

  # The types fixture's functions as dagger functions lists them.
  DESCRIPTIONS = {
    "echo" => "A string, back unchanged.",
    "negate" => "A boolean, negated.",
    "maybe" => "An optional string: the same, or null.",
    "next-mood" => "The next mood; the default is a member.",
    "exec-error" => "An ExecError from the API, rescued: its exit code and stderr."
  }.freeze

  # Each function's arguments as dagger call <function> --help lists them,
  # whitespace squeezed: the type, the default and whether it is required.
  # The CLI hides a function that takes a module object or an interface.
  ARGUMENTS = {
    "echo" => ["--text string [required]"],
    "succ" => ["--number int [required]"],
    "half" => ["--number float [required]"],
    "negate" => ["--flag [required]"],
    "maybe" => ["--text string"],
    "reversed" => ["--items strings [required]"],
    "next-mood" => ["--mood CALM,GRUMPY,HAPPY (default CALM)"],
    "pair" => ["--left string [required]", "--right string [required]", "--mood CALM,GRUMPY,HAPPY (default HAPPY)"],
    "size" => ["--file File [required]"],
    "entries" => ["--dir Directory [required]"],
    "defaults" => ['--name string (default "world")', "--times int (default 2)", "--ratio float (default 0.5)",
                   "--loud"]
  }.freeze

  function "A new module's template is annotated and passes Steep, installed from its lock's development group; a " \
           "wrong result type fails Steep, and an annotation that disagrees with its def fails generation, naming " \
           "its file and line.", check: true
  #: (ws: Core::Workspace) -> void
  def annotations_check(ws:)
    ws = fixtures(ws)
    scope = "#{OUT}/typed"
    generated = generate(ws.with_new_directory(path: "/#{scope}", source: core.directory), scope, name: "typed")
    root = generated.directory(path: "/#{scope}")
    source = root.file(path: "lib/typed.rb").contents
    check_includes(source, CONTAINER_ANNOTATION, "the template has no annotation")
    passed = steep(ws, root)
    check(passed.end_with?("steep-exit=0\n"), "Steep failed on the template: #{passed}")

    wrong = root.with_new_file(path: "lib/typed.rb", contents: source.sub(CONTAINER_ANNOTATION, "#: () -> String"))
    failed = steep(ws, wrong)
    check(failed.include?("Cannot allow method body have type `::Dagger::Clients::Core::Container` because " \
                          "declared as type `::String`") && !failed.end_with?("steep-exit=0\n"),
          "Steep passed a wrong result type: #{failed}")

    bad = with_function(source, BAD_FUNCTION)
    line = bad.lines.index { it.include?("def bad(nam:)") } + 1
    seeded = generated.with_new_file(path: "/#{scope}/lib/typed.rb", contents: bad)
    error = refusal { generate(seeded, scope, name: "typed") }
    check_includes(error.to_s, "lib/typed.rb:#{line}: Typed.bad: its annotation takes (name:) but the def takes (nam:)",
                   "a disagreeing annotation was not refused at its line")
  end

  function "dagger functions shows each function's description, and dagger call --help each argument's type, " \
           "default and requiredness, as the annotations and defs of the types fixture give them.", check: true
  #: (ws: Core::Workspace) -> void
  def functions_listing_check(ws:)
    ws = fixtures(ws)
    ground = playground(ws)
    listed = squeezed(cli(ground, "-m", TYPES, "functions").stdout)
    DESCRIPTIONS.each { |name, doc| check_includes(listed, "#{name} #{doc}", "dagger functions") }
    ARGUMENTS.each do |function, arguments|
      help = squeezed(cli(ground, "-m", TYPES, "call", function, "--help").stdout)
      arguments.each { check_includes(help, it, "dagger call #{function} --help") }
    end
  end

  STEEP_MODULES = %w[steep-broken steep-clean].freeze
  # What a call's container installed: the group it skips, and Steep's gems.
  GEMS_FUNCTION = <<~'RUBY'.freeze
    function "The call's Bundler group and Steep's gems."
    #: () -> String
    def gems = "#{ENV.fetch("BUNDLE_WITHOUT", "")} #{Dir.glob("/usr/local/bundle/ruby/*/gems/steep-*").size}"
  RUBY
  GHOST_GEM = %(gem "dagger-clients-ghost", path: "clients/ghost"\n).freeze
  UNANNOTATED_FUNCTION = %(function "Greetings"\ndef hello(name:)\n  "Hello \#{name}"\nend\n).freeze

  function "dagger check runs the SDK's Steep check on every Ruby module the SDK generated, and names each that " \
           "fails with Steep's output; dagger call ruby-sdk mod --path checks one; plain scopes, the SDK module and " \
           "a module without a Steepfile are not checked, a module dagger generate would refuse fails with " \
           "generation's message even where Steep passes, and a module's own container stays without the " \
           "development group.", check: true
  #: (ws: Core::Workspace) -> void
  def modules_steep_check(ws:)
    ws = fixtures(ws)
    generated = steep_modules(ws)
    lib = "/steep-broken/lib/steep_broken.rb"
    wrong = generated.file(path: lib).contents.sub(CONTAINER_ANNOTATION, "#: () -> String")
    broken = generated.with_new_file(path: lib, contents: wrong)
    ground = playground(ws, broken.directory(path: "/", exclude: EXCLUDED + [FIXTURES]))
    failed = cli_failure(ground, "check", "ruby-sdk:steep")
    ["The Steep check failed in 1 of 3 Ruby modules: steep-broken", "steep-broken: bundle exec steep check exited 1",
     "Cannot allow method body have type `::Dagger::Clients::Core::Container` because declared as type `::String`",
     "checked: .dagger/modules/e2e, steep-broken, steep-clean",
     "generation checks ok: .dagger/modules/e2e, steep-broken, steep-clean",
     "steep skipped, no Steepfile: .dagger/modules/e2e"].each do |want|
      check_includes(failed, want, "dagger check ruby-sdk:steep")
    end
    check_excludes(failed, "steep-clean: bundle exec", "dagger check ruby-sdk:steep failed the clean module")
    check_excludes(failed, "steep-plain", "dagger check ruby-sdk:steep took a plain scope for a module")

    cli(ground, "call", "ruby-sdk", "mod", "--path", "steep-clean", "steep")
    single = cli_failure(ground, "call", "ruby-sdk", "mod", "--path", "steep-broken/lib", "steep")
    check(single.include?("declared as type `::String`") &&
          single.include?("The Steep check failed in 1 of 1 Ruby modules: steep-broken"),
          "dagger call ruby-sdk mod --path steep-broken/lib steep: #{single}")
    invariant(ws, generated)
    fixed(ws, generated)
  end

  private

  # Two modules from the default template, one with a function that reports
  # its own container's gems, and a plain scope beside them.
  def steep_modules(ws)
    seeded = (STEEP_MODULES + ["steep-plain"]).reduce(ws) do |seed, scope|
      seed.with_new_directory(path: "/#{scope}", source: core.directory)
    end
    generated = generate(STEEP_MODULES.reduce(seeded) { |seed, name| generate(seed, name, name:) }, "steep-plain",
                         is_module: false)
    lib = "/steep-clean/lib/steep_clean.rb"
    reporting = generated.with_new_file(path: lib, contents: with_function(generated.file(path: lib).contents,
                                                                           GEMS_FUNCTION))
    generate(reporting, "steep-clean", name: "steep-clean")
  end

  # A passing check means dagger generate accepts the module. For each class
  # of what generation refuses, an edit made after generation: the check
  # fails on it with generation's own message. Annotated, the function that
  # had none passes the check, generates, and generates again to no change.
  def invariant(ws, generated)
    lib = "/steep-clean/lib/steep_clean.rb"
    source = generated.file(path: lib).contents
    refusal_cases(generated, lib, source).map { |what, tree| Thread.new { refused_alike(ws, what, tree) } }
                                         .each(&:value)
    unannotated = with_function(source, UNANNOTATED_FUNCTION)
    line = unannotated.lines.index { it.include?("def hello(name:)") } + 1
    all = cli_failure(steep_ground(ws, generated.with_new_file(path: lib, contents: unannotated)), "check",
                      "ruby-sdk:steep")
    check_includes(all, "The Steep check failed in 1 of 3 Ruby modules: steep-clean", "dagger check ruby-sdk:steep")
    check_includes(all, "steep-clean: describing the module failed: dagger-mod: Dagger::Mod::RegistrationError: " \
                        "lib/steep_clean.rb:#{line}: SteepClean.hello has no annotation that generation read; write " \
                        "its type on the line above the def, as #: (name: String) -> String",
                   "dagger check ruby-sdk:steep")
    annotated = with_function(source, UNANNOTATED_FUNCTION.sub("def hello", "#: (name: String) -> String\ndef hello"))
    generated_again(ws, generated.with_new_file(path: lib, contents: annotated))
  end

  # Generation's refusal, its message as RubySdk::Error gives it, is the
  # check's.
  def refused_alike(ws, what, tree)
    said = refusal { generate(tree, "steep-clean", name: "steep-clean") }.to_s
    message = said[/RubySdk::Error: (.+)$/, 1]
    check(message, "#{what}: dagger generate did not refuse it: #{said}")
    single = cli_failure(steep_ground(ws, tree), "call", "ruby-sdk", "mod", "--path", "steep-clean", "steep")
    check(single.include?(message), "#{what}: the check did not refuse it with #{message.inspect}: #{single}")
  end

  # What the check passes, dagger generate accepts, and a second generation
  # changes nothing.
  def generated_again(ws, tree)
    cli(steep_ground(ws, tree), "call", "ruby-sdk", "mod", "--path", "steep-clean", "steep")
    once = generate(tree, "steep-clean", name: "steep-clean")
    twice = generate(once, "steep-clean", name: "steep-clean")
    check(same_files?(twice.directory(path: "/steep-clean"), once.directory(path: "/steep-clean")),
          "a second dagger generate changed the module the check passed")
  end

  def steep_ground(ws, tree) = playground(ws, tree.directory(path: "/", exclude: EXCLUDED + [FIXTURES]))

  # what => the workspace with one edit dagger generate refuses: the
  # module's types, its client roots, its scope, its Gemfile.
  def refusal_cases(generated, lib, source)
    root = "/steep-clean"
    field = "  field :base_image_address #: String\n"
    edit = ->(added) { generated.with_new_file(path: lib, contents: with_function(source, added)) }
    {
      "a function without an annotation" => edit.call(UNANNOTATED_FUNCTION),
      "an annotation that disagrees with its def" => edit.call(BAD_FUNCTION),
      "a field without a type" =>
        generated.with_new_file(path: lib, contents: source.sub(field, "#{field}  field :extra\n")),
      "an annotation that does not parse" =>
        edit.call(%[function "Broken."\n#: (name: String -> String\ndef broken(name:) = name\n]),
      "a type the API cannot carry" => edit.call(%(function "Symbol."\n#: () -> Symbol\ndef symbol = :a\n)),
      "a type that names no constant" => edit.call(%(function "Nope."\n#: () -> Nope\ndef nope = nil\n)),
      "a function named like a client method" => edit.call(%(function "Core."\n#: () -> String\ndef core = ""\n)),
      "a manifest key" => generated.with_new_file(
        path: "#{root}/dagger-module.toml",
        contents: %(engineVersion = "latest"\n#{generated.file(path: "#{root}/dagger-module.toml").contents})
      ),
      "a dagger.json" => generated.with_new_file(path: "#{root}/dagger.json", contents: "{}\n"),
      "clients/roots not generation's" => generated.without_file(path: "#{root}/clients/roots/.dagger-generated"),
      "another SDK gem in the Gemfile" => generated.with_new_file(
        path: "#{root}/Gemfile",
        contents: "#{generated.file(path: "#{root}/Gemfile").contents}#{GHOST_GEM}"
      )
    }
  end

  # The same modules, fixed: the check passes, and a call still runs in a
  # container without the development group.
  def fixed(ws, generated)
    ground = playground(ws, generated.directory(path: "/", exclude: EXCLUDED + [FIXTURES]))
    cli(ground, "check", "ruby-sdk:steep")
    gems = cli(ground, "-m", "steep-clean", "call", "gems").stdout.strip
    check(gems == "development 0", "a call ran with #{gems.inspect}, not without Steep and its group")
    check_includes(file_in(ground, "steep-clean/sdk/entrypoint/build.dang"),
                   %(.withEnvVariable("BUNDLE_WITHOUT", "development")), "the module's build")
  end

  # Steep as an author runs it: the lock's development group, installed in
  # the module's image.
  def steep(ws, scope)
    image = ws.file(path: "/images/ruby/Dockerfile").contents[/^FROM (\S+)/, 1]
    core.container.from(address: image)
        .with_directory(path: "/src", source: scope)
        .with_workdir(path: "/src")
        .with_env_variable(name: "BUNDLE_FROZEN", value: "true")
        .with_exec(args: %w[bundle install])
        .with_exec(args: ["sh", "-c", "bundle exec steep check 2>&1; echo steep-exit=$?"])
        .stdout
  end

  def squeezed(text) = text.gsub(/\e\[[0-9;]*m/, "").lines.map { it.split.join(" ") }.join("\n")
end
