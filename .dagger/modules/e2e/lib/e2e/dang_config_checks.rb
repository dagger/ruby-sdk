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
    dang_config_settings(ws)
    dang_config_conflicts(ws)
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

    pinned = %(dang = "2.1"\n\n[imports.Dagger]\ndagger = "v1.0.0-beta.19"\n)
    older = generate(ws.with_new_file(path: app_config, contents: pinned), APP, name: "app")
    check_versioned(older.file(path: app_config).contents, target_version(ws), "the replaced older version")
  end

  def dang_config_conflicts(ws)
    {
      %(dang = "2.0"\n) => %(dang = "2.0"),
      %([imports.Dagger]\npath = "./mine"\n) => "imports.Dagger.path",
      %([imports.Dagger]\ndagger = true\nendpoint = "http://localhost"\n) => "imports.Dagger.endpoint",
      %([imports.Other]\ndagger = "v1.0.0-beta.19"\n) => "imports.Other.dagger",
      "dang = [\n" => "not valid TOML"
    }.each do |toml, named|
      error = refusal { generate(ws.with_new_file(path: app_config, contents: toml), APP, name: "app") }
      check(error.to_s.include?("cannot carry") && error.include?(named), "#{named} was not refused: #{error.inspect}")
    end
  end

  def dang_config_ancestors(ws)
    ancestor = "/#{APP}/dang.toml"
    pinned = %([imports.Dagger]\ndagger = "v1.0.0-beta.19"\n)
    bare = ws.without_file(path: app_config)

    error = refusal { generate(bare.with_new_file(path: ancestor, contents: pinned), APP, name: "app") }
    check(error.to_s.include?("would hide") && error.include?("imports.Dagger"),
          "a new dang.toml hid the ancestor's pin: #{error.inspect}")

    plain = %(dang = "2.1"\n)
    made = generate(bare.with_new_file(path: ancestor, contents: plain), APP, name: "app")
    check(made.file(path: ancestor).contents == plain, "generation wrote to an ancestor it does not hide")
    check_versioned(made.file(path: app_config).contents, target_version(ws), "the dang.toml beside an ancestor")

    above = "/#{FIXTURES}/dang.toml"
    seeded = ws.with_new_file(path: ancestor, contents: pinned).with_new_file(path: above, contents: pinned)
    kept = generate(seeded, APP, name: "app")
    check(kept.file(path: ancestor).contents == pinned, "generation wrote to an ancestor already hidden")
    check(kept.file(path: above).contents == pinned, "generation wrote above the module")

    dang_config_sdk_ancestor(ws, bare)
  end

  def dang_config_sdk_ancestor(ws, bare)
    ancestor = "/#{APP}/sdk/dang.toml"
    custom = %([imports.Lib]\npath = "./lib"\n)
    hidden = generate(ws.with_new_file(path: ancestor, contents: custom), APP, name: "app")
    check(hidden.file(path: ancestor).contents == custom, "replacing sdk/ changed a hidden sdk/dang.toml")

    accepted = %(dang = "2.1"\n)
    first = generate(bare.with_new_file(path: ancestor, contents: accepted), APP, name: "app")
    check(first.file(path: ancestor).contents == accepted, "replacing sdk/ changed an accepted sdk/dang.toml")
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
