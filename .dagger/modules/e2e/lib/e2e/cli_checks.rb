class E2E
  RELEASE = ["call", "container", "file", "--path", "/etc/alpine-release", "contents"].freeze

  function "With the SDK installed by path from this repository's dagger.toml, dagger sdk list shows ruby, and " \
           "dagger module init ruby writes a module that runs, with the default " \
           "and the empty template; both include the scope's client roots, the default one runs core through " \
           "them, and dagger functions lists no client method.", check: true
  #: (ws: Core::Workspace) -> void
  def cli_sdk_check(ws:)
    ws = fixtures(ws)
    listed = cli(playground(ws), "sdk", "list")
    check_includes(listed.stdout, "ruby", "dagger sdk list did not list the Ruby SDK")

    path = ".dagger/modules/sdk-smoke"
    initialized = cli(listed, "module", "init", "ruby", "-y", "--name", "sdk-smoke", "--path", path)
    %w[dagger-module.toml Gemfile Gemfile.lock dagger.gemfile lib/sdk_smoke.rb sdk/dagger-sdk.gemspec
       sdk/entrypoint/main.dang clients/core/lib/dagger/clients/core.rb].each do |file|
      check(exists_in(initialized, "#{path}/#{file}"), "dagger module init did not write #{file}")
    end
    check(!exists_in(initialized, "#{path}/dagger.json"), "dagger module init wrote a dagger.json")
    check(file_in(initialized, "#{path}/dagger-module.toml") == manifest("sdk-smoke"),
          "the manifest is not name and [entrypoint]")
    source = file_in(initialized, "#{path}/lib/sdk_smoke.rb")
    ['require "dagger/clients/roots"', "include Dagger::Clients::Roots", "    core.container.from("].each do |want|
      check_includes(source, want, "the default template")
    end
    release = cli(initialized, "-m", path, *RELEASE).stdout
    check(!release.strip.empty?, "the new module did not run")
    listed = cli(initialized, "-m", path, "functions").stdout.lines.map { it.split.first }
    check(listed.include?("container") && !listed.include?("core"), "dagger functions listed #{listed}")

    empty = cli(initialized, "module", "init", "ruby", "-y", "--name", "sdk-empty",
                "--path", ".dagger/modules/sdk-empty", "--template", "empty")
    source = file_in(empty, ".dagger/modules/sdk-empty/lib/sdk_empty.rb")
    check_includes(source, "class SdkEmpty", "the empty template")
    check_includes(source, "include Dagger::Clients::Roots", "the empty template")
    check_excludes(source, "def container", "the empty template has a function")
  end

  # name => lib/ file. A module runs only if its main class is the one the
  # engine names with strcase.ToCamel; e2e, the harness's own name, is another.
  MODULE_NAMES = {
    "module3" => "module3", "MyModule" => "my_module", "HTTPServer" => "http_server", "p11lib" => "p11lib",
    "s3-bucket" => "s3_bucket"
  }.freeze

  function "Modules named module3, MyModule, HTTPServer, p11lib and s3-bucket initialise, regenerate and run, so " \
           "the SDK names their main classes as the engine does; as clients, their methods are the engine's " \
           "constructor fields in snake case.", check: true
  #: (ws: Core::Workspace) -> void
  def cli_module_name_check(ws:)
    ws = fixtures(ws)
    initialized = MODULE_NAMES.reduce(playground(ws)) do |ground, (name, file)|
      cli(ground, "module", "init", "ruby", "-y", "--name", name, "--path", ".dagger/modules/named-#{file}")
    end
    made = cli(initialized, "generate", "-y")
    MODULE_NAMES.each do |name, file|
      path = ".dagger/modules/named-#{file}"
      check(exists_in(made, "#{path}/lib/#{file}.rb"), "#{name} has no lib/#{file}.rb")
      ran = cli(made, "-m", path, *RELEASE).stdout
      check(!ran.strip.empty?, "the module #{name} did not run")
    end
    client_methods(made)
  end

  # Each client's method is the engine's constructor field for its module,
  # in snake case.
  CLIENT_METHODS = %(core: "core", httpserver: "HTTPServer", module3: "module3", my_module: "MyModule", ) +
                   %(p11_lib: "p11lib", s3_bucket: "s3-bucket")

  def client_methods(made)
    names = ".dagger/modules/names"
    ground = cli(made, "module", "init", "ruby", "-y", "--name", "names", "--path", names, "--template", "empty")
    ground = MODULE_NAMES.each_value.reduce(ground) do |built, file|
      cli(built, "module", "client", "add", "../named-#{file}", "--sdk", "ruby", "-y", workdir: names)
    end
    roots = file_in(ground, "#{names}/clients/roots/lib/dagger/clients/roots.rb")
    check_includes(roots, "def self.clients = { #{CLIENT_METHODS} }.freeze", "the client methods of odd names")
  end

  function "dagger module init ruby --ruby-version writes .ruby-version, and regeneration keeps it.", check: true
  #: (ws: Core::Workspace) -> void
  def settings_check(ws:)
    ws = fixtures(ws)
    path = ".dagger/modules/settings"
    initialized = cli(playground(ws), "module", "init", "ruby", "-y", "--name", "settings", "--path", path,
                      "--ruby-version", "3.4")
    check(file_in(initialized, "#{path}/.ruby-version") == "3.4\n", "the --ruby-version setting was not written")
    config = file_in(initialized, "dagger.toml")
    check(config.match?(%r{scopes\.".dagger/modules/settings"\.settings\]\n(?:.*\n)*?\w+ = "3\.4"}),
          "dagger.toml does not record the setting: #{config}")
    regenerated = cli(initialized, "generate", "-y")
    check(file_in(regenerated, "#{path}/.ruby-version") == "3.4\n", "regeneration lost .ruby-version")

    [[CONFIG_APP, "config-app"], [CONFIGURED, "config-configured"]].each do |scope, name|
      changes = changed(generate(ws, scope, name:), ws)
      check(changes.is_empty, "regenerating #{scope} without a setting changed it: #{paths(changes)}")
    end
  end
end
