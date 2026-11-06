class E2E
  SETTINGS = <<~TOML.freeze
    # the user's own comment
    dang = "2.1"

    [imports.Dagger]
    dagger = true
    service = ["./bin/dagger", "session"]

    [imports.Lib]
    path = "./lib"
  TOML

  function "A module's dang.toml names the target version its entrypoint declares, in Dang 2.1: generation keeps " \
           "other settings, replaces the Dagger version, refuses what contradicts them, leaves ancestors alone, " \
           "keeps the cwd, and changes nothing the second time.", check: true
  #: (ws: Core::Workspace) -> void
  def dang_config_check(ws:)
    ws = fixtures(ws)
    dang_config_default(ws)
    dang_config_root_module(ws)
    dang_config_settings(ws)
    dang_config_helper_rules(ws)
    dang_config_ancestors(ws)
    dang_config_plain(ws)
  end

  private

  def app_config = "/#{APP}/sdk/entrypoint/dang.toml"

  # By its settings: TOML.encode chooses the layout, which indents nested tables.
  def check_versioned(toml, version, what)
    check_includes(toml, %(dang = "2.1"\n), "#{what} is not on Dang 2.1")
    check_includes(toml, "[imports.Dagger]", "#{what} has no Dagger import")
    check_includes(toml, %(dagger = "#{version}"\n), "#{what} does not name #{version}")
  end

  def dang_config_default(ws)
    [[APP, "app"], ["#{FIXTURES}/include/app", "include-app"]].each do |scope, name|
      entrypoint = ws.directory(path: "/#{scope}/sdk/entrypoint")
      check_versioned(entrypoint.file(path: "dang.toml").contents, target_version(ws), "#{name}'s dang.toml")
      check_includes(entrypoint.file(path: "main.dang").contents,
                     %(let clientVersion: String! = "#{target_version(ws)}"\n),
                     "#{name}'s entrypoint does not declare the target version dang.toml names")
      check_includes(entrypoint.file(path: "main.dang").contents,
                     %(.withEnvVariable("DAGGER_CLIENT_VERSION", clientVersion)),
                     "#{name}'s entrypoint does not set the client version")
      again = changed(generate(ws, scope, name:), ws)
      check(again.is_empty, "regenerating #{name} changed it: #{paths(again)}")
    end
    made = generate(ws, APP, name: "app")
    check(made.cwd == ws.with_workdir(path: APP).cwd, "generateScope changed the workspace cwd: #{made.cwd}")
  end

  def dang_config_root_module(ws)
    root = core.directory.with_new_file(path: "README.md", contents: "a module at the root\n").as_workspace
    made = generate(root, ".", name: "root-app")
    check(made.cwd == root.with_workdir(path: ".").cwd, "generateScope changed the root's cwd: #{made.cwd}")
    check_versioned(made.file(path: "/sdk/entrypoint/dang.toml").contents, target_version(ws), "the root's dang.toml")
    again = changed(generate(made, ".", name: "root-app"), made)
    check(again.is_empty, "regenerating the root module changed it: #{paths(again)}")
  end

  def dang_config_settings(ws)
    seeded = ws.with_new_file(path: app_config, contents: SETTINGS)
    made = generate(seeded, APP, name: "app")
    toml = made.file(path: app_config).contents
    check_versioned(toml, target_version(ws), "the rewritten dang.toml")
    ["./bin/dagger", "session", "[imports.Lib]", "./lib"].each do |kept|
      check_includes(toml, kept, "the settings were not kept")
    end
    check_excludes(toml, "dagger = true", "the owned import was not replaced")
    check_excludes(toml, "the user's own comment", "dang.toml is expected to be rewritten whole")
    again = changed(generate(made, APP, name: "app"), made)
    check(again.is_empty, "regenerating the rewritten settings changed them: #{paths(again)}")

    pinned = %(dang = "2.0"\n\n[imports.Dagger]\ndagger = "v1.0.0-beta.19"\n)
    older = generate(ws.with_new_file(path: app_config, contents: pinned), APP, name: "app")
    check_versioned(older.file(path: app_config).contents, target_version(ws), "the replaced older version")
  end

  def dang_config_helper_rules(ws)
    pathed = generate(ws.with_new_file(path: app_config, contents: %([imports.Dagger]\npath = "./mine"\n)), APP,
                      name: "app")
    toml = pathed.file(path: app_config).contents
    check_excludes(toml, "./mine", "the Dagger import kept its path")
    check_versioned(toml, target_version(ws), "the dang.toml without a path")

    endpoint = %([imports.Dagger]\ndagger = true\nendpoint = "http://localhost"\n)
    error = refusal { generate(ws.with_new_file(path: app_config, contents: endpoint), APP, name: "app") }
    check_includes(error.to_s, "has an endpoint", "the sdk-helpers endpoint error did not surface")
  end

  def dang_config_ancestors(ws)
    ancestor = "/#{APP}/dang.toml"
    above = "/#{FIXTURES}/dang.toml"
    pinned = %([imports.Dagger]\ndagger = "v1.0.0-beta.19"\n)
    seeded = ws.without_file(path: app_config).with_new_file(path: ancestor, contents: pinned)
               .with_new_file(path: above, contents: pinned)
    made = generate(seeded, APP, name: "app")
    check(made.file(path: ancestor).contents == pinned, "generation changed the module's dang.toml")
    check(made.file(path: above).contents == pinned, "generation changed a dang.toml above the module")
    check_versioned(made.file(path: app_config).contents, target_version(ws), "the dang.toml beside an ancestor")
  end

  def dang_config_plain(ws)
    bare = ws.directory(path: "/#{PLAIN}")
    check(!bare.exists(path: "sdk/entrypoint"), "a plain scope got an entrypoint directory")

    leftover = "/#{PLAIN}/sdk/entrypoint/dang.toml"
    client = ws.module_source(path: "/#{DEP}")
    kept = generate(ws.with_new_file(path: leftover, contents: SETTINGS), PLAIN, is_module: false, clients: [client])
    check(kept.file(path: leftover).contents == SETTINGS, "pruning the entrypoint lost its configuration")
  end
end
