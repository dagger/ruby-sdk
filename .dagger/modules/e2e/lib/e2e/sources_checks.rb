class E2E
  INCLUDE = "#{FIXTURES}/include".freeze
  INCLUDE_APP = "#{INCLUDE}/app".freeze
  INCLUDE_CALLER = "#{INCLUDE}/caller".freeze
  WORD = "#{INCLUDE}/shared/lib/shared/word.txt".freeze
  SOURCES = '.withDirectory(cwd + "/../shared", workspace.directory("../shared", exclude: [".bundle", ' \
            '"vendor/bundle"], gitignore: true))'.freeze

  function "A module that uses a path gem outside its directory returns it from its entrypoint's sources and " \
           "builds from its context; a module without one keeps its entrypoint; generating again changes nothing, " \
           "and writes nothing outside the module.", check: true
  #: (ws: Core::Workspace) -> void
  def sources_generate_check(ws:)
    entrypoint = "#{INCLUDE_APP}/sdk/entrypoint"
    check_includes(ws.file(path: "/#{entrypoint}/main.dang").contents, SOURCES, "the include app's main.dang")
    check_includes(ws.file(path: "/#{entrypoint}/build.dang").contents, 'let anchor = subpath.trimSuffix("app")',
                   "the include app's build.dang")
    control = ws.directory(path: "/#{APP}/sdk/entrypoint")
    check_excludes(control.file(path: "main.dang").contents, "pub sources", "the control module's main.dang")
    check_excludes(control.file(path: "build.dang").contents, "subpath", "the control module's build.dang")
    again = generate(ws, INCLUDE_APP, name: "include-app")
    changes = changed(again, ws)
    check(changes.is_empty, "generating the include app again changed #{paths(changes)}")
  end

  function "A call reads the path gem outside the module; a second session reuses its result, and an edit to " \
           "the gem gives a new one, through the module and through a caller's client.", check: true
  #: (ws: Core::Workspace) -> void
  def sources_call_check(ws:)
    ground = playground(ws)
    call = ->(container, mod, function) { cli(container, "-m", mod, "call", function).stdout.strip }
    check(call.call(ground, INCLUDE_APP, "word") == "one", "the include app's word is not the gem's")
    nonce = call.call(ground, INCLUDE_APP, "nonce")
    check(call.call(ground, INCLUDE_APP, "nonce") == nonce, "a second session did not reuse the result")
    check(call.call(ground, INCLUDE_CALLER, "word") == "one", "the caller's word is not the gem's")
    edited = ground.with_new_file(path: "#{PLAYGROUND}/#{WORD}", contents: "two\n")
    check(call.call(edited, INCLUDE_APP, "word") == "two", "an edit to the gem did not reach the call")
    check(call.call(edited, INCLUDE_APP, "nonce") != nonce, "an edit to the gem reused the old result")
    check(call.call(edited, INCLUDE_CALLER, "word") == "two", "an edit to the gem did not reach the caller")
  end

  function "The engine runs the contract each entrypoint declares: the include app, with sources, gets no " \
           "workspace in types and call, the control module keeps it, and the engine lists the functions of both.",
           check: true
  #: (ws: Core::Workspace) -> void
  def sources_contract_check(ws:)
    included = ws.file(path: "/#{INCLUDE_APP}/sdk/entrypoint/main.dang").contents
    check_includes(included, "  pub types: [TypeDef!]! {\n", "the include app's types")
    check_includes(included, "  pub call(\n    receiverType: String!,\n", "the include app's call")
    control = ws.file(path: "/#{APP}/sdk/entrypoint/main.dang").contents
    check_includes(control, "  pub types(workspace: Workspace!): [TypeDef!]! {\n", "the control module's types")
    check_includes(control, "  pub call(\n    workspace: Workspace!,\n", "the control module's call")
    ground = playground(ws)
    { INCLUDE_APP => %w[nonce word], APP => %w[greet version] }.each do |mod, functions|
      listed = cli(ground, "-m", mod, "functions").stdout
      functions.each { check_includes(listed, it, "the functions of #{mod}") }
    end
  end

  function "The engine keys a call on what sources returns and nothing else outside the module: a file beside " \
           "the gem, or an edit in the gem's Bundler directories, leaves the result as it was.", check: true
  #: (ws: Core::Workspace) -> void
  def sources_scope_check(ws:)
    shared = "#{PLAYGROUND}/#{INCLUDE}/shared"
    bundler = lambda do |ground, contents|
      ground.with_new_file(path: "#{shared}/.bundle/config", contents:)
            .with_new_file(path: "#{shared}/vendor/bundle/notes.txt", contents:)
    end
    ground = bundler.call(playground(ws), "one\n")
    nonce = cli(ground, "-m", INCLUDE_APP, "call", "nonce").stdout.strip
    elsewhere = bundler.call(ground, "two\n").with_new_file(path: "#{PLAYGROUND}/#{INCLUDE}/notes.txt",
                                                            contents: "notes\n")
    again = cli(elsewhere, "-m", INCLUDE_APP, "call", "nonce").stdout.strip
    check(again == nonce, "a file outside what sources returns gave a new result")
  end

  function "Generation refuses a path gem it cannot load with the module, naming the Gemfile's line, and so does " \
           "the Steep check; a Gemfile that names a gem outside without dagger generate fails the call with the " \
           "hint to run it.", check: true
  #: (ws: Core::Workspace) -> void
  def sources_refusals_check(ws:)
    gemfile = "/#{INCLUDE_APP}/Gemfile"
    base = ws.file(path: gemfile).contents
    {
      'File.expand_path("../shared", __dir__)' => "Gemfile:5: path: is not a string literal",
      '"/opt/shared"' => 'Gemfile:5: "/opt/shared" is absolute',
      '"../../../../../../../shared"' => "leaves the workspace's root",
      '"../missing"' => 'Gemfile:5: "../missing" names nothing in the workspace'
    }.map do |path, want|
      tree = ws.with_new_file(path: gemfile, contents: base.sub('"../shared"', path))
      Thread.new { refused_both(tree, want) }
    end.each(&:value)
    stale(ws, base)
  end

  function "A module that uses a path gem outside its directory loads by a git ref, with the gem from the same " \
           "commit.", check: true
  #: (ws: Core::Workspace) -> void
  def sources_git_check(ws:)
    server = include_server(ws)
    ground = development_image(ws).with_file(path: "/usr/local/bin/dagger", source: ws.file(path: "/#{CLI_PATH}"))
                                  .with_service_binding(alias_: "git-server", service: server)
                                  .with_workdir(path: "/tmp")
    word = ground.with_exec(args: ["dagger", "-m", "git://#{server.hostname}/include.git#main:app", "call", "word"],
                            experimental_privileged_nesting: true).stdout.strip
    check(word == "one", "the include app by a git ref said #{word.inspect}")
  end

  private

  def refused_both(tree, want)
    said = refusal { generate(tree, INCLUDE_APP, name: "include-app") }.to_s
    check_includes(said, want, "dagger generate")
    check_includes(steep_refusal(tree), want, "the Steep check")
  end

  # The Steep check returns nothing; its failure is the SDK module's.
  def steep_refusal(tree)
    sdk.mod(ws: tree, path: INCLUDE_APP).steep
    ""
  rescue Dagger::ExecError => e
    "#{e.message}\n#{e.stderr}"
  rescue Dagger::QueryError => e
    e.message
  end

  # A gem outside added to the Gemfile without dagger generate.
  def stale(ws, base)
    other = "#{PLAYGROUND}/#{INCLUDE}/other"
    ground = playground(ws).with_new_file(path: "#{PLAYGROUND}/#{INCLUDE_APP}/Gemfile",
                                          contents: %(#{base}gem "other", path: "../other"\n))
                           .with_new_file(path: "#{other}/other.gemspec",
                                          contents: %(Gem::Specification.new { it.name = "other"; it.version = "1" }\n))
    failed = cli_failure(ground, "-m", INCLUDE_APP, "call", "word")
    check_includes(failed, "run `dagger generate`", "a call after a Gemfile edit without dagger generate")
  end

  # The generated include fixtures, committed whole, as a repository would
  # serve them.
  def include_server(ws)
    commit = "git init --quiet --initial-branch main && git add --all && " \
             "git -c user.name=e2e -c user.email=e2e@dagger.io commit --quiet --no-gpg-sign --message include && " \
             "git clone --quiet --bare /repo /srv/include.git"
    development_image(ws).with_directory(path: "/repo", source: ws.directory(path: "/#{INCLUDE}", exclude: EXCLUDED))
                         .with_workdir(path: "/repo")
                         .with_exec(args: ["sh", "-c", commit])
                         .with_exposed_port(port: 9418)
                         .as_service(args: %w[git daemon --reuseaddr --export-all --base-path=/srv --listen=0.0.0.0
                                              /srv])
  end
end
