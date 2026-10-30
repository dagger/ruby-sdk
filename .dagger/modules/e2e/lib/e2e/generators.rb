class E2E
  function "test/fixtures/core-schema.json is the engine's client-facing schema, and the goldens are rendered " \
           "from it.", generator: true
  #: (ws: Core::Workspace) -> Core::Changeset
  def goldens(ws:)
    before = tree(ws)
    test = development_image(ws).with_directory(path: "/src", source: before)
                                .with_workdir(path: "/src")
                                .with_exec(args: %w[ruby test/refresh.rb], experimental_privileged_nesting: true)
                                .directory(path: "/src/test")
    before.with_directory(path: "test", source: test).changes(from: before)
  end

  function "The root's plain scope, which holds the SDK module's own core client: the SDK's generation skips it.",
           generator: true
  #: (ws: Core::Workspace) -> Core::Changeset
  def root_scope(ws:) = changed(generate(ws, ".", is_module: false), ws)
end
