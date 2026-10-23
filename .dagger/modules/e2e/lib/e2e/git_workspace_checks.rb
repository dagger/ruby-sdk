class E2E
  GIT_WORKSPACE = <<~TOML.freeze
    [modules.ruby-sdk]
    source = "."

    [sdks.ruby]
    module = "ruby-sdk"

    [sdks.ruby.scopes."#{TYPES}"]
    is-module = true
    name = "types"
    clients = ["./#{DEP}"]
  TOML

  function "A workspace opened from a git ref generates what its checkout generates. There a client of a module " \
           "of the same repository resolves as a git source at the workspace's commit; generation still binds it " \
           "by path, with the ref's selector and without one.", check: true
  #: (ws: Core::Workspace) -> void
  def git_workspace_generate_check(ws:)
    ground = playground(ws).with_new_file(path: "#{PLAYGROUND}/dagger.toml", contents: GIT_WORKSPACE)
    generates_nothing(ground, "", "generating from the checkout")

    server = git_server(ws, ground.directory(path: PLAYGROUND).without_directory(path: ".git"))
    # The engine takes a git ref whose host has no dot for a Go import path
    # and refuses it: the ref names the server by its full name, in the
    # session domain that resolv.conf searches last.
    repo = "git://#{server.hostname}.$(awk '/^search/ {print $NF}' /etc/resolv.conf)/ruby-sdk.git"
    served = ground.with_service_binding(alias_: server.hostname, service: server)
    generates_nothing(served, %(-W "#{repo}@main"), "generating from the git ref at main")
    generates_nothing(served, %(-W "#{repo}"), "generating from the git ref without a selector")
  end

  private

  # The CLI reports an empty changeset in a log line, which plain progress
  # prints, and a changeset it does not apply as a summary near the end of
  # its output.
  def generates_nothing(container, flags, what)
    attempt = container.with_workdir(path: PLAYGROUND)
                       .with_exec(args: ["sh", "-c", "dagger --progress=plain #{flags} generate --no-apply"],
                                  experimental_privileged_nesting: true, expect: Core::ReturnType::ANY)
    output = attempt.stderr
    check(attempt.exit_code.zero? && output.include?("no changes to apply") &&
            !output.include?("Generated changes were not applied"),
          "#{what} changed the files generated from the checkout:\n#{output.lines.last(80).join}")
  end
end
