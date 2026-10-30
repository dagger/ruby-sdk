class E2E
  # The program runs in a copy of the tree in the container: Bundler writes
  # the scope's lock.
  PLAIN_PROGRAM = <<~SH.freeze
    set -eu
    bundle install >/dev/null
    ran=$(dagger run --progress=plain ruby -rbundler/setup hello.rb 2>/tmp/run.log) || { cat /tmp/run.log; exit 1; }
    [ "$ran" = "hello, plain" ] || { echo "under dagger run, it printed: $ran"; exit 1; }
    ran=$(ruby -rbundler/setup hello.rb)
    [ "$ran" = "hello, plain" ] || { echo "with a session it provisions, it printed: $ran"; exit 1; }
    ran=$(dagger run --progress=plain ruby -rbundler/setup roots.rb 2>/tmp/run.log) || { cat /tmp/run.log; exit 1; }
    [ "$ran" = "$(printf 'hello, from the top level\\nhello, from a class')" ] ||
      { echo "through the client roots, it printed: $ran"; exit 1; }
    if pgrep -f "^[^ ]*dagger session" >/dev/null; then
      echo "left behind: $(pgrep -af "^[^ ]*dagger session")"; exit 1
    fi
  SH

  function "A plain Ruby program calls a client under dagger run and with a session it provisions, and leaves no " \
           "dagger session behind; another calls it through the client roots, from the top level and from a " \
           "class. It runs in an exec with a session of its own, whose CLI serves dagger run's child.", check: true
  #: (ws: Core::Workspace) -> void
  def plain_program_check(ws:)
    ws = fixtures(ws)
    ran = playground(ws).with_workdir(path: "#{PLAYGROUND}/#{PLAIN}")
                        .with_exec(args: ["sh", "-c", PLAIN_PROGRAM], dagger_in_dagger_new_session: true,
                                   expect: Core::ReturnType::ANY)
    check(ran.exit_code.zero?, "the plain program failed: #{ran.stdout}#{ran.stderr}")
  end
end
