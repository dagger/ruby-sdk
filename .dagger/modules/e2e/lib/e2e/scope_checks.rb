class E2E
  USER_FILES = {
    "clients/tools/Gemfile" => "source \"https://rubygems.org\"\n",
    "clients/notes/README.md" => "not a member\n",
    "clients/handmade/.dagger-generated" => "client (by hand)\n", "clients/handmade/secret.txt" => "mine\n",
    "clients/blank/.dagger-generated" => "", "clients/blank/secret.txt" => "mine\n",
    "clients/capital/.dagger-generated" => "Client", "clients/capital/secret.txt" => "mine\n",
    "clients/nomarker/secret.txt" => "mine\n"
  }.freeze

  USER_GEMFILE = <<~RUBY.freeze
    # the user's own comment
    source "https://rubygems.org"

    gem "rake", "~> 13.0" # a pin of the user's

    group :development do
      gem "irb"
    end
  RUBY

  function "findClientRoot answers with the directory of the nearest Gemfile, lifts a member to its scope, " \
           "and answers null where there is none.", check: true
  #: (ws: Core::Workspace) -> void
  def find_client_root_check(ws:)
    ws = fixtures(ws)
    {
      "#{LOOKUP}/nested" => LOOKUP,
      LOOKUP => LOOKUP,
      "#{LOOKUP}/sdk/lib/dagger" => LOOKUP,
      "#{PLAIN}/clients/core/lib" => PLAIN,
      "sdk/lib/dagger/mod" => ".",
      "." => "."
    }.each do |cwd, want|
      got = sdk.find_client_root(ws: ws.with_workdir(path: cwd))
      check(got == want, "findClientRoot from #{cwd}: got #{got.inspect}, want #{want.inspect}")
    end
    # This repository's root is a scope, so a workspace of its own has no Gemfile.
    bare = core.directory.with_new_file(path: "README.md", contents: "no Gemfile\n").as_workspace
    check(sdk.find_client_root(ws: bare).nil?, "findClientRoot found a scope in a workspace without a Gemfile")
  end

  function "generateScope initialises a module: the template, the manifest and the scope tree, with the cwd " \
           "and existing files untouched; settings pick the template and the Ruby.", check: true
  #: (ws: Core::Workspace) -> void
  def generate_scope_init_check(ws:)
    scope = "#{OUT}/scope-init"
    scoped = ws.with_new_directory(path: "/#{scope}", source: core.directory)
               .with_new_file(path: "/#{scope}/keep.txt", contents: "keep\n")
    generated = generate(scoped, scope, name: "scope-init")
    changes = changed(generated, scoped)

    check(generated.cwd == scoped.with_workdir(path: scope).cwd, "generateScope changed the workspace cwd")
    %w[dagger-module.toml Gemfile Gemfile.lock dagger.gemfile .gitignore .gitattributes Steepfile lib/scope_init.rb
       sdk/.dagger-generated sdk/dagger-sdk.gemspec sdk/exe/dagger-mod sdk/entrypoint/main.dang
       sdk/entrypoint/dang.toml sdk/entrypoint/types.dang sdk/entrypoint/build.dang sdk/entrypoint/signatures.json
       sdk/entrypoint/module.rbs clients/core/.dagger-generated
       clients/core/lib/dagger/clients/core.rb clients/roots/.dagger-generated
       clients/roots/dagger-clients-roots.gemspec clients/roots/lib/dagger/clients/roots.rb
       clients/roots/sig/dagger/clients/roots.rbs].each do |path|
      check_includes(changes.added_paths, "#{scope}/#{path}", "initialising did not add #{path}")
    end
    check_excludes(changes.added_paths, "#{scope}/dagger.json", "initialising wrote a dagger.json")
    check(changes.modified_paths.empty? && changes.removed_paths.empty?,
          "initialising changed files: #{paths(changes)}")

    root = generated.directory(path: "/#{scope}")
    check(root.file(path: "dagger-module.toml").contents == manifest("scope-init"),
          "the manifest is not name and [entrypoint]")
    source = root.file(path: "lib/scope_init.rb").contents
    ["class ScopeInit", "extend Dagger::Mod::Object", "include Dagger::Clients::Roots",
     "#: (ws: Dagger::Clients::Core::Workspace, ?base_image_address: String) -> ScopeInit",
     "#: () -> Dagger::Clients::Core::Container", "def container", "    core.container.from("].each do |want|
      check_includes(source, want, "the default template")
    end
    check_excludes(source, "{{", "the template left a placeholder")
    check_includes(root.file(path: "Gemfile").contents, EVAL_LINE, "the new Gemfile does not evaluate dagger.gemfile")
    check_includes(root.file(path: "clients/core/lib/dagger/clients/core/workspace.rb").contents, "def cwd",
                   "core lacks Workspace#cwd, so it is not the engine's current view")
    check(!root.exists(path: ".ruby-version"), "a .ruby-version was written without the setting")

    configured_scope = "#{OUT}/scope-init-configured"
    configured = generate(ws.with_new_directory(path: "/#{configured_scope}", source: core.directory), configured_scope,
                          name: "scope-init-configured", with: sdk(template: "empty", ruby_version: "3.4"))
                 .directory(path: "/#{configured_scope}")
    source = configured.file(path: "lib/scope_init_configured.rb").contents
    check_includes(source, "class ScopeInitConfigured", "the empty template")
    check_includes(source, "include Dagger::Clients::Roots", "the empty template")
    roots = root.file(path: "clients/roots/lib/dagger/clients/roots.rb").contents
    check_includes(roots, "def self.clients = { core: \"core\" }.freeze", "a scope without clients has core alone")
    check_excludes(source, "def container", "the empty template has a function")
    check(configured.file(path: ".ruby-version").contents == "3.4\n", "the ruby-version setting was not written")
  end

  function "generateScope regenerates an existing module and keeps the user's files; a dagger.json is refused, " \
           "not migrated.", check: true
  #: (ws: Core::Workspace) -> void
  def generate_scope_existing_check(ws:)
    ws = fixtures(ws)
    regenerated = changed(generate(ws, APP, name: "app"), ws)
    check(regenerated.is_empty, "regenerating the generated app changed it: #{paths(regenerated)}")

    edited = ws.with_new_file(path: "/#{APP}/notes.txt", contents: "mine\n")
               .with_new_file(path: "/#{APP}/lib/app/extra.rb", contents: "class App\n  EXTRA = 1\nend\n")
    after = changed(generate(edited, APP, name: "app"), edited)
    check(after.is_empty, "regenerating after an edit that declares nothing changed the module: #{paths(after)}")

    error = refusal { generate(ws.with_new_file(path: "/#{APP}/dagger.json", contents: "{}"), APP, name: "app") }
    check(error.to_s.include?("dagger.json") && error.include?("remove dagger.json"),
          "a dagger.json was not refused: #{error.inspect}")
  end

  function "Adding a client writes its member, one dagger.gemfile line and its method in the client roots, and " \
           "relocks; removing it undoes all three; a manifest with [[dependencies]] is refused.", check: true
  #: (ws: Core::Workspace) -> void
  def generate_scope_clients_check(ws:)
    ws = fixtures(ws)
    client = ws.module_source(path: "/#{DEP}")
    manifest_path = "/#{APP}/dagger-module.toml"
    seeded = ws.with_new_file(path: manifest_path, contents: "#{ws.file(path: manifest_path).contents}\n" \
                                                             "[[dependencies]]\nname = \"dep\"\nsource = \"../dep\"\n")
    error = refusal { generate(seeded, APP, name: "app", clients: [client]) }
    check(error.to_s.include?("[[dependencies]]") && error.include?("dagger module client add"),
          "a manifest with [[dependencies]] was not refused: #{error.inspect}")

    with = generate(ws, APP, name: "app", clients: [client])
    added = changed(with, ws)
    check(added.removed_paths.empty?, "adding a client removed files: #{added.removed_paths}")
    check(added.added_paths.all? { it.start_with?("#{APP}/clients/dep/") }, "adding a client added files outside " \
                                                                            "its member: #{added.added_paths}")
    allowed = %w[dagger.gemfile Gemfile.lock sdk/entrypoint/build.dang clients/roots/lib/dagger/clients/roots.rb
                 clients/roots/sig/dagger/clients/roots.rbs].map { "#{APP}/#{it}" }
    check(added.modified_paths.sort == allowed.sort, "adding a client modified #{added.modified_paths}")

    root = with.directory(path: "/#{APP}")
    check(root.file(path: "dagger-module.toml").contents == manifest("app"), "a client reached the manifest")
    check_includes(root.file(path: "dagger.gemfile").contents, %(gem "dagger-clients-dep", path: "clients/dep"\n),
                   "dagger.gemfile does not load the client")
    check_includes(root.file(path: "Gemfile.lock").contents, "dagger-clients-dep", "the lock misses the client")
    check(root.file(path: "clients/dep/.dagger-generated").contents == "client", "the member is not marked a client")
    target = root.file(path: "clients/dep/lib/dagger/clients/dep/target.rb").contents
    [%(NAME = "dep"), %(REF = "/#{DEP}"), "PIN = nil", %(CORE_DIGEST = "#{core_digest(root)}")].each do |want|
      check_includes(target, want, "the client's target")
    end
    check_includes(root.file(path: "clients/dep/lib/dagger/clients/dep.rb").contents, "def self.dep(",
                   "the client has no entry function")
    roots = root.file(path: "clients/roots/lib/dagger/clients/roots.rb").contents
    method = "def dep(session: nil)\n        ::Dagger::Clients::Dep.dep(session:)"
    [%(require "dagger/clients/dep"), method].each { check_includes(roots, it, "the client roots lack the method") }

    removed = changed(generate(with, APP, name: "app"), ws)
    check(removed.is_empty, "removing the client did not undo adding it: #{paths(removed)}")
  end

  PINNED = "64645f1967d3dba6fce951dd61ae4acd8d9b0861".freeze
  REPINNED = "92d07fcb9dd25ae50afd30097f09936d674c2950".freeze
  HELPERS = "github.com/dagger/sdk-helpers@main".freeze

  function "A git client records the commit its ref resolved to, and a newly resolved commit replaces it.",
           check: true
  #: (ws: Core::Workspace) -> void
  def generate_scope_pins_check(ws:)
    ws = fixtures(ws)
    target = core.module_source(ref_string: HELPERS, ref_pin: PINNED)
    descriptor = "/#{APP}/clients/sdk_helpers/lib/dagger/clients/sdk_helpers/target.rb"
    input = ws.with_new_file(path: "/#{APP}/keep.txt", contents: "keep")
    pinned = generate(input, APP, name: "app", clients: [target])
    check_includes(pinned.file(path: descriptor).contents, %(REF = "#{target.as_string}"), "the git client's ref")
    check_includes(pinned.file(path: descriptor).contents, %(PIN = "#{PINNED}"), "the git client's pin")
    check_excludes(pinned.file(path: "/#{APP}/dagger-module.toml").contents, "sdk-helpers",
                   "a client reached the manifest")

    updated = core.module_source(ref_string: HELPERS, ref_pin: REPINNED)
    repinned = generate(pinned, APP, name: "app", clients: [updated])
    check_includes(repinned.file(path: descriptor).contents, %(PIN = "#{REPINNED}"),
                   "the new commit did not replace the pin")
    check(repinned.cwd == pinned.cwd, "generation changed the cwd")
    check(repinned.file(path: "/#{APP}/keep.txt").contents == "keep", "generation changed another file")
    repeated = changed(generate(repinned, APP, name: "app", clients: [updated]), repinned)
    check(repeated.is_empty, "repeated generation changed the workspace: #{paths(repeated)}")
  end

  function "A scope without a module gets the same members and no module files; a member is byte-identical " \
           "whichever scope holds it.", check: true
  #: (ws: Core::Workspace) -> void
  def generate_scope_plain_check(ws:)
    ws = fixtures(ws)
    scope = "#{OUT}/plain-scope"
    client = ws.module_source(path: "/#{DEP}")
    bare = ws.with_new_directory(path: "/#{scope}", source: core.directory)

    empty = generate(bare, scope, is_module: false).directory(path: "/#{scope}")
    check(empty.file(path: "sdk/.dagger-generated").contents == "sdk", "sdk/ is not marked as the SDK's")
    check(empty.file(path: "clients/core/.dagger-generated").contents == "core", "clients/core is not marked as core")
    check_includes(empty.file(path: "Gemfile").contents, EVAL_LINE, "the new Gemfile does not evaluate dagger.gemfile")
    %w[dagger-module.toml sdk/entrypoint Gemfile.lock lib].each do |path|
      check(!empty.exists(path:), "a scope without a module got #{path}")
    end

    plain = generate(bare, scope, is_module: false, clients: [client]).directory(path: "/#{scope}")
    check_includes(plain.file(path: "dagger.gemfile").contents, %(gem "dagger-clients-dep", path: "clients/dep"),
                   "dagger.gemfile does not load the client")
    module_scope = generate(ws, APP, name: "app", clients: [client]).directory(path: "/#{APP}")
    check(empty.file(path: "clients/roots/.dagger-generated").contents == "roots", "clients/roots is not marked")
    %w[clients/dep clients/core clients/roots].each do |member|
      difference = plain.directory(path: member).changes(from: module_scope.directory(path: member))
      check(difference.is_empty,
            "#{member} differs between a scope without a module and a module: #{paths(difference)}")
    end
    check(same_files?(plain.directory(path: "sdk"),
                      module_scope.directory(path: "sdk").without_directory(path: "entrypoint")),
          "sdk/ differs between a scope without a module and a module")

    fixture = changed(generate(ws, PLAIN, is_module: false, clients: [client]), ws)
    check(fixture.is_empty, "regenerating the generated plain scope changed it: #{paths(fixture)}")
  end

  function "The SDK owns dagger.gemfile, its members and one Gemfile line: the user's Gemfile, and what is under " \
           "clients/ without the marker, survive and are never written over.", check: true
  #: (ws: Core::Workspace) -> void
  def generate_scope_user_content_check(ws:)
    ws = fixtures(ws)
    scope = "#{OUT}/user-content"
    client = ws.module_source(path: "/#{DEP}")
    files = USER_FILES.merge("Gemfile" => USER_GEMFILE, "clients/stale/.dagger-generated" => "client\n",
                             "clients/stale/a.rb" => "")
    generated = generate(seeded(ws, scope, files), scope, is_module: false, clients: [client])
    gemfile = generated.file(path: "/#{scope}/Gemfile").contents
    check(gemfile == "#{USER_GEMFILE}\n#{EVAL_LINE}\n", "the Gemfile changed beyond the one line: #{gemfile.inspect}")
    again = generate(generated, scope, is_module: false, clients: [client]).file(path: "/#{scope}/Gemfile").contents
    check(again == gemfile, "a second generation changed the Gemfile again: #{again.inspect}")
    check(!generated.directory(path: "/#{scope}").exists(path: "clients/stale"),
          "a client marked as such, with a final newline, that no client claims was kept")

    removed(generated, scope)
    refusals(ws, scope, client)
  end

  function "Generation reports only what it produced: files a scope already has are not added.", check: true
  #: (ws: Core::Workspace) -> void
  def generate_skips_existing_files_check(ws:)
    ws = fixtures(ws)
    scope = "#{OUT}/skips"
    existing = {
      "Gemfile" => "source \"https://rubygems.org\"\n",
      ".gitattributes" => "* text=auto\n",
      "lib/skips.rb" => "require \"dagger\"\n\nclass Skips\n  extend Dagger::Mod::Object\nend\n"
    }
    base = seeded(ws, scope, existing)
    changes = changed(generate(base, scope, name: "skips"), base)

    existing.each_key { check_excludes(changes.added_paths, "#{scope}/#{it}", "generation reported #{it} as added") }
    check(changes.modified_paths == ["#{scope}/Gemfile"], "generation modified #{changes.modified_paths}")
    check_includes(changes.added_paths, "#{scope}/.gitignore", "the template's missing file was not added")
  end

  function "A scope vendors the library alone: lib/, sig/, exe/, the gemspec and LICENSE, and in a module the " \
           "entrypoint; never tests, the generator or development files.", check: true
  #: (ws: Core::Workspace) -> void
  def vendoring_check(ws:)
    ws = fixtures(ws)
    vendored = generate(ws, APP, name: "app").directory(path: "/#{APP}/sdk")
    entries = vendored.entries.sort
    want = %w[.dagger-generated LICENSE dagger-sdk.gemspec entrypoint/ exe/ lib/ sig/]
    check(entries == want, "sdk/ holds #{entries}, not #{want}")
    check(same_files?(vendored.directory(path: "lib"), ws.directory(path: "/sdk/lib")),
          "sdk/lib is not the library")
    check(same_files?(vendored.directory(path: "sig"), ws.directory(path: "/sdk/sig")),
          "sdk/sig is not the library's signatures")
    check(vendored.directory(path: "exe").entries == ["dagger-mod"], "sdk/exe holds more than dagger-mod")
    check(vendored.directory(path: "entrypoint").entries.sort ==
            %w[build.dang dang.toml main.dang module.rbs signatures.json types.dang],
          "sdk/entrypoint holds more than the generated entrypoint")
  end

  function "The manifest is exactly name and [entrypoint]; what manifest version 2 on the generated entrypoint " \
           "cannot carry is refused, naming it.", check: true
  #: (ws: Core::Workspace) -> void
  def manifest_check(ws:)
    ws = fixtures(ws)
    path = "/#{APP}/dagger-module.toml"
    {
      "the manifest generation wrote" => manifest("app"),
      "keys reordered and quoted otherwise" =>
        %(name = 'app'\n\n[ entrypoint ]\nsource = './sdk/entrypoint'\nkind = "dang"\n),
      "a module rooted at its own directory" => %(name = "app"\nsource = "."\n),
      "another name" => %(name = "other"\n)
    }.each do |what, toml|
      written = generate(ws.with_new_file(path:, contents: toml), APP, name: "app").file(path:).contents
      check(written == manifest("app"), "#{what} was regenerated as #{written.inspect}")
    end

    {
      %(name = "app"\n\n[runtime]\nsource = "ruby"\n) => "[runtime]",
      %(name = "app"\n\n[[dependencies]]\nname = "dep"\nsource = "../dep"\n) => "[[dependencies]]",
      %(name = "app"\ninclude = ["lib"]\n) => "include",
      %(name = "app"\nexclude = ["tmp"]\n) => "exclude",
      %(name = "app"\nsource = "lib"\n) => "source",
      %(name = "app"\nengineVersion = "v1.0.0"\n) => "engineVersion",
      %(name = "app"\ndisableDefaultFunctionCaching = true\n) => "disableDefaultFunctionCaching",
      %(name = "app"\n\n[entrypoint]\nkind = "dang"\nsource = "./other"\n) => "[entrypoint] source",
      %(name = "app"\n\n[entrypoint]\nkind = "module"\nsource = "./sdk/entrypoint"\n) => "[entrypoint] kind",
      %(name = [\n) => "not valid TOML"
    }.each do |toml, key|
      error = refusal { generate(ws.with_new_file(path:, contents: toml), APP, name: "app") }
      check(error.to_s.include?("cannot carry") && error.include?(key), "#{key} was not refused: #{error.inspect}")
    end
  end

  function "A function with a cache policy and an unknown template are refused before anything is written.",
           check: true
  #: (ws: Core::Workspace) -> void
  def refusals_check(ws:)
    ws = fixtures(ws)
    source = ws.file(path: "/#{APP}/lib/app.rb").contents
    cached = with_function(source, %(function "Cached.", cache: "never"\n#: () -> String\ndef cached = "x"\n))
    error = refusal { generate(ws.with_new_file(path: "/#{APP}/lib/app.rb", contents: cached), APP, name: "app") }
    check_includes(error.to_s, "cache policy", "a cache policy was not refused")

    scope = "#{OUT}/legacy"
    legacy = ws.with_new_directory(path: "/#{scope}", source: core.directory)
    error = refusal { generate(legacy, scope, name: "legacy", with: sdk(template: "legacy")) }
    check_includes(error.to_s, %(no template "legacy"), "an unknown template was not refused")
  end

  private

  def seeded(ws, scope, files)
    files.reduce(ws) { |seed, (path, contents)| seed.with_new_file(path: "/#{scope}/#{path}", contents:) }
  end

  def removed(generated, scope)
    removed = generate(generated, scope, is_module: false)
    check(!removed.directory(path: "/#{scope}").exists(path: "clients/dep"), "a removed client's member stayed")
    check_excludes(removed.file(path: "/#{scope}/dagger.gemfile").contents, "dagger-clients-dep",
                   "a removed client stayed in dagger.gemfile")
    USER_FILES.each_key do |path|
      check(generated.directory(path: "/#{scope}").exists(path:), "generation deleted #{path}")
      check(removed.directory(path: "/#{scope}").exists(path:), "removing a client deleted #{path}")
    end
  end

  def refusals(ws, scope, client)
    squatted = seeded(ws, scope, "clients/dep/mine.txt" => "mine\n")
    error = refusal { generate(squatted, scope, is_module: false, clients: [client]) }
    check(error.to_s.include?("clients/dep/ exists") && error.include?("move or rename it"),
          "a client was written over a directory without the marker: #{error.inspect}")

    foreign = seeded(ws, scope, "clients/core/.dagger-generated" => "hand-written")
    error = refusal { generate(foreign, scope, is_module: false) }
    check_includes(error.to_s, "clients/core/ exists", "core was written over a member of another kind")

    own = seeded(ws, scope, "sdk/lib/mine.rb" => "# mine\n")
    error = refusal { generate(own, scope, is_module: false) }
    check_includes(error.to_s, "sdk/ exists", "the SDK was written over the user's sdk/")
  end
end
