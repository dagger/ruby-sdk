class E2E
  # name => main class, lib/ file, client directory, client constant. The
  # main class is strcase.ToCamel's, which the engine names the module with.
  NAMES = {
    "my-module" => %w[MyModule my_module my_module MyModule],
    "my_module" => %w[MyModule my_module my_module MyModule],
    "myModule" => %w[MyModule my_module mymodule Mymodule],
    "MyModule" => %w[MyModule my_module mymodule Mymodule],
    "HTTPServer" => %w[Httpserver http_server httpserver Httpserver],
    "s3-bucket" => %w[S3Bucket s3_bucket s3_bucket S3Bucket],
    "app2" => %w[App2 app2 app2 App2],
    "e2e" => %w[E2E e2e e2e E2e],
    "p11lib" => %w[P11Lib p11lib p11lib P11lib]
  }.freeze

  RAINBOW = <<~'RUBY'.freeze
    function "A user gem's version."
    #: (build: String) -> String
    def rainbow(build:)
      require "rainbow"
      "#{build} #{Gem.loaded_specs.fetch("rainbow").version}"
    end

    function "When the user gem was installed."
    #: () -> String
    def installed_at = File.mtime(Gem.loaded_specs.fetch("rainbow").full_gem_path).strftime("%s.%N")
  RUBY

  SHOUT = %(function "Shout."\n#: () -> String\ndef shout = "HEY"\n).freeze
  REGENERATE_HINT = "if you changed declarations, clients or gems, run `dagger generate`".freeze

  NAMING = <<~RUBY.freeze
    require "json"
    require "dagger/mod"
    require "ruby_sdk/codegen/naming"
    naming = RubySdk::Codegen::Naming
    puts JSON.generate(ARGV.to_h do |name|
      [name, [Dagger::Mod::Naming.to_camel(name), Dagger::Mod::Naming.file_name(name), naming.client_file(name),
              naming.client_constant(name)]]
    end)
  RUBY

  function "dagger functions loads a generated module, so the engine evaluates its rendered types.dang.",
           check: true
  #: (ws: Core::Workspace) -> void
  def types_load_check(ws:)
    source = with_function(ws.file(path: "/#{APP}/lib/app.rb").contents, SHOUT)
    generated = generate(ws.with_new_file(path: "/#{APP}/lib/app.rb", contents: source), APP, name: "app")
    listed = cli(playground(ws, tree(generated)), "-m", APP, "functions").stdout
    %w[greet version shout].each { check_includes(listed, it, "dagger functions did not list #{it}") }
  end

  function "A function body edited without dagger generate runs at once and returns the new result; so does a " \
           "permission-only change.", check: true
  #: (ws: Core::Workspace) -> void
  def edit_without_generate_check(ws:)
    files = tree(ws)
    helper = "#{APP}/lib/app/greeting.rb"
    call = ["-m", APP, "call", "greet", "--name", core.version]
    edited = files.with_new_file(path: helper, contents: files.file(path: helper).contents.sub("!", ", edited!"))
    ran = cli(playground(ws, edited), *call).stdout
    check_includes(ran, "hello, #{core.version}, edited!", "the edited body did not run")
    chmod = files.with_file(path: helper, source: files.file(path: helper), permissions: 0o755)
    ran = cli(playground(ws, chmod), *call).stdout
    check_includes(ran, "hello, #{core.version}!", "a permission-only change did not run")
  end

  function "Without dagger generate, a new function is unknown to the CLI, and a changed signature, a missing " \
           "client, a stripped clients/core or an edited Gemfile show Ruby's or Bundler's own error, then the hint " \
           "to run dagger generate.", check: true
  #: (ws: Core::Workspace) -> void
  def missed_generation_check(ws:)
    files = tree(ws)
    main = "#{APP}/lib/app.rb"
    source = files.file(path: main).contents
    shout = files.with_new_file(path: main, contents: with_function(source, SHOUT))
    check_includes(cli_failure(playground(ws, shout), "-m", APP, "call", "shout"), 'unknown command "shout"',
                   "a function added without dagger generate")
    renamed = source.sub("#: (?name: String) -> String", "#: (?who: String) -> String")
                    .sub('def greet(name: "world") = Greeting.new(greeting).to(name)',
                         'def greet(who: "world") = Greeting.new(greeting).to(who)')
    gemfile = "#{files.file(path: "#{APP}/Gemfile").contents}gem \"rainbow\", \"3.1.1\"\n"
    with_gem = files.with_new_file(path: "#{APP}/Gemfile", contents: gemfile)
    {
      "App.greet: the method takes (?who:) but its annotation took (?name:)" =>
        files.with_new_file(path: main, contents: renamed),
      "cannot load such file -- dagger/clients/other (LoadError)" =>
        files.with_new_file(path: main, contents: %(require "dagger/clients/other"\n#{source})),
      "The path `/src/clients/core` does not exist." => files.without_directory(path: "#{APP}/clients/core"),
      "* rainbow (= 3.1.1)" => with_gem
    }.each do |error, changed|
      failed = cli_failure(playground(ws, changed), "-m", APP, "call", "greet", "--name", core.version)
      check(failed.include?(error) && failed.include?(REGENERATE_HINT),
            "without dagger generate, wanted #{error.inspect} and the hint: #{failed}")
    end
  end

  function "A module installs its path gems with its lock, installs a user gem and keeps it installed across an " \
           "edit to lib/, and with .ruby-version builds and locks on that Ruby.", check: true
  #: (ws: Core::Workspace) -> void
  def module_build_check(ws:)
    ground = playground(ws)
    greeting = cli(ground, "-m", APP, "call", "greet", "--name", core.version).stdout.strip
    check(greeting == "hello, #{core.version}!", "the module answered #{greeting.inspect}")

    user_gem(ws)

    { CONFIG_APP => "4.0.", CONFIGURED => "3.4." }.each do |path, want|
      ruby = cli(ground, "-m", path, "call", "ruby-version").stdout.strip
      check(ruby.start_with?(want), "#{path} ran on Ruby #{ruby}, not #{want}x")
    end
    bundlers = [APP, CONFIGURED].map { ws.file(path: "/#{it}/Gemfile.lock").contents[/^BUNDLED WITH\n\s+(\S+)/, 1] }
    check(bundlers.uniq.size == 2, "the ruby:3.4 module was not locked by its own Bundler: #{bundlers}")
  end

  function "The SDK's naming rules over a table of names: main class, lib/ file, client directory and constant. " \
           "cliModuleNameCheck checks main classes against the engine.", check: true
  #: (ws: Core::Workspace) -> void
  def naming_check(ws:)
    output = development_image(ws).with_directory(path: "/module", source: ws.directory(path: "/lib"))
                                  .with_directory(path: "/sdk", source: ws.directory(path: "/sdk/lib"))
                                  .with_new_file(path: "/naming.rb", contents: NAMING)
                                  .with_exec(args: ["ruby", "-I/sdk", "-I/module", "/naming.rb", *NAMES.keys])
                                  .stdout
    got = JSON.parse(output)
    NAMES.each { |name, want| check(got[name] == want, "#{name} names #{got[name]}, not #{want}") }
  end

  function "dagger generate over every registered scope, the SDK module's Ruby half and this harness included, " \
           "changes nothing.", check: true
  #: (ws: Core::Workspace) -> void
  def generated_up_to_date_check(ws:)
    before = tree(ws)
    after = cli(playground(ws, before), "generate", "-y").directory(path: PLAYGROUND).filter(exclude: [".git"])
    changes = after.changes(from: before)
    check(changes.is_empty, "dagger generate changed the tree: #{paths(changes)}")
  end

  private

  def user_gem(ws)
    gemfile = "#{ws.file(path: "/#{APP}/Gemfile").contents}gem \"rainbow\", \"3.1.1\"\n"
    source = with_function(ws.file(path: "/#{APP}/lib/app.rb").contents, RAINBOW)
    seeded = ws.with_new_file(path: "/#{APP}/Gemfile", contents: gemfile)
               .with_new_file(path: "/#{APP}/lib/app.rb", contents: source)
    with_gem = generate(seeded, APP, name: "app")
    check_includes(with_gem.file(path: "/#{APP}/Gemfile.lock").contents, "rainbow (3.1.1)",
                   "the lock misses the user gem")
    ground = playground(ws, tree(with_gem))
    ran = cli(ground, "-m", APP, "call", "rainbow", "--build", core.version).stdout.strip
    check(ran == "#{core.version} 3.1.1", "the user gem did not load: #{ran.inspect}")
    kept_installed(ws, with_gem, cli(ground, "-m", APP, "call", "installed-at").stdout.strip)
  end

  # The engine caches the install by its inputs: after an edit to lib/, the
  # gems are the ones installed before, with the time of that install.
  def kept_installed(ws, with_gem, before)
    helper = "/#{APP}/lib/app/greeting.rb"
    contents = with_gem.file(path: helper).contents.sub("!", ", again!")
    edited = playground(ws, tree(with_gem.with_new_file(path: helper, contents:)))
    greeted = cli(edited, "-m", APP, "call", "greet", "--name", core.version).stdout
    check_includes(greeted, "hello, #{core.version}, again!", "the edit to lib/ did not run")
    after = cli(edited, "-m", APP, "call", "installed-at").stdout.strip
    check(after == before, "an edit to lib/ reinstalled the gems: installed at #{before}, then at #{after}")
  end
end
