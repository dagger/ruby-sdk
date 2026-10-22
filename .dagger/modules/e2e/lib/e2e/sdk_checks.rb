class E2E
  function "Minitest passes on the library, the SDK module and the generator.", check: true
  #: (ws: Core::Workspace) -> void
  def sdk_test_check(ws:) = unit(ws, "test")

  function "RuboCop passes on the repository.", check: true
  #: (ws: Core::Workspace) -> void
  def sdk_lint_check(ws:) = unit(ws, "lint")

  function "Steep passes on the library, the SDK module and the generated core.", check: true
  #: (ws: Core::Workspace) -> void
  def sdk_types_check(ws:) = unit(ws, "types")

  private

  def unit(ws, step)
    development_image(ws).with_directory(path: "/src", source: tree(ws))
                         .with_workdir(path: "/src")
                         .with_exec(args: ["ruby", "hack/unit.rb", step])
                         .sync
    nil
  end
end
