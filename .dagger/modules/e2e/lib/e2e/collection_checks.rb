class E2E
  COLLECTIONS = "#{FIXTURES}/collections/app".freeze
  COLLECTIONS_CALLER = "#{FIXTURES}/collections/caller".freeze

  function "A collection through dagger call and the API: keys, get, list, subset, batch, its delta after a " \
           "subset and after a change of keys, with marked members and with the engine's member names.", check: true
  #: (ws: Core::Workspace) -> void
  def collections_check(ws:)
    ws = fixtures(ws)
    ground = playground(ws)
    call = ->(*args) { JSON.parse(cli(ground, "-m", COLLECTIONS, "call", "--json", *args).stdout) }
    {
      %w[items keys] => %w[b a c],
      %w[items get --key=a name] => "item:a",
      %w[items name --collections-item=a] => "item:a",
      %w[items selected --collections-item=a --collections-item=c] => %w[a c],
      %w[suites keys] => %w[unit lint],
      %w[suites get --key=lint name] => "lint"
    }.each do |args, want|
      got = call.call(*args)
      check(got == want, "#{args.join(" ")}: got #{got.inspect}, want #{want.inspect}")
    end
    collection_queries(ws)
  end

  function "A Ruby module calls a collection module through its generated client: subset, batch, get and list.",
           check: true
  #: (ws: Core::Workspace) -> void
  def collection_client_check(ws:)
    ws = fixtures(ws)
    ground = playground(ws)
    {
      "subset-keys" => %w[b c], "removed" => %w[b c], "item" => "item:a", "names" => %w[item:b item:a item:c]
    }.each do |function, want|
      got = JSON.parse(cli(ground, "-m", COLLECTIONS_CALLER, "call", "--json", function).stdout)
      check(got == want, "#{function}: got #{got.inspect}, want #{want.inspect}")
    end
  end

  function "dagger check runs a collection's checks: one per item of its item type, and one per item of a " \
           "collection's own check.", check: true
  #: (ws: Core::Workspace) -> void
  def collection_checks_check(ws:)
    ws = fixtures(ws)
    ground = playground(ws)
    links = cli(ground, "-m", COLLECTIONS, "check", "--module", "collections", "-l", "--all", "-f=link").stdout.split
    want = %w[complete&collections-suite=lint complete&collections-suite=unit verify&collections-item=a
              verify&collections-item=b verify&collections-item=c]
    # v1.0.0-beta.19 also names the collection's field: check=items/verify.
    named = links.map { it.sub(%r{check=\w+/}, "check=") }
    check(named.sort == want.map { "dag+check://?check=#{it}" }, "dagger check -l --all listed #{links.inspect}")
    item_c = links.find { it.end_with?("item=c") }
    cli(ground, "-m", COLLECTIONS, "check", *(links - [item_c])).sync
    check_includes(cli_failure(ground, "-m", COLLECTIONS, "check", item_c), "item c fails its check",
                   "the check of item c")
  end

  function "A function returns core artifacts, which the CLI selects on, and reads them in the module.", check: true
  #: (ws: Core::Workspace) -> void
  def artifacts_check(ws:)
    ws = fixtures(ws)
    ground = playground(ws)
    call = ->(*args) { JSON.parse(cli(ground, "-m", COLLECTIONS, "call", "--json", *args).stdout) }
    selected = call.call("artifacts", "--ws", ".", "dimensions")
    read = call.call("dimensions", "--ws", ".")
    check(selected.include?("module") && selected == read, "artifacts gave #{selected.inspect}, read #{read.inspect}")
  end

  private

  # The projected API, as the engine's own collection test queries it, of
  # the module served from the workspace with the generated fixtures.
  def collection_queries(ws)
    ws.module_source(path: "/#{COLLECTIONS}").as_module.serve
    root = Dagger::QueryBuilder.new.select("collections")
    items = root.select("items")
    subset = items.select("subset", keys: %w[c b])
    changed = items.select("batch").select("change", names: %w[c d]).select("batch")
    suites = root.select("suites")
    {
      "list" => [items.select("list").select("name").execute, %w[item:b item:a item:c].map { { "name" => it } }],
      "subset keys" => [subset.select("keys").execute, %w[b c]],
      "subset removed" => [subset.select("batch").select("removed").execute, %w[a]],
      "empty subset" => [items.select("subset", keys: []).select("batch").select("removed").execute, %w[b a c]],
      "changed added" => [changed.select("added").execute, %w[d]],
      "changed removed" => [changed.select("removed").execute, %w[b a]],
      "a check that passes" => [suites.select("batch").select("complete").select("pass").execute, true],
      "a check that fails" => [suites.select("subset", keys: %w[unit]).select("batch").select("complete")
                                     .select("pass").execute, false]
    }.each { |what, (got, want)| check(got == want, "#{what}: got #{got.inspect}, want #{want.inspect}") }
  end
end
