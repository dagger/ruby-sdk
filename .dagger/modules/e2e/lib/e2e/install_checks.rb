class E2E
  INSTALLED = "/work/app".freeze
  SDK_FILES = {
    "sdk/lib/dagger.rb" => "# decoy\n",
    "templates/default/lib/{{file}}.rb.tmpl" => "# decoy\n",
    "images/ruby/Dockerfile" => "FROM decoy\n",
    "lib/ruby_sdk.rb" => "raise 'decoy'\n"
  }.freeze
  DECOYS = {
    "by a git ref" => {},
    "with a decoy module/ in the workspace" => SDK_FILES.transform_keys { "module/#{it}" },
    "with files at the SDK's own paths in the workspace" => SDK_FILES
  }.freeze

  function "The SDK installed by a git ref to this repository's root, served by a git server, generates a module " \
           "from its own files, and never from files of the workspace at the same paths.", check: true
  #: (ws: Core::Workspace) -> void
  def sdk_installed_by_git_ref_check(ws:)
    server = git_server(ws)
    DECOYS.each do |what, decoys|
      made = installed_by_git_ref(ws, server, decoys).directory(path: INSTALLED)
      check(made.exists(path: "hello/dagger-module.toml"), "#{what}: no module was made")
      check(same_files?(made.directory(path: "hello/sdk/lib"), ws.directory(path: "/sdk/lib")),
            "#{what}: the generated sdk/ is not the SDK's own")
      check_includes(made.file(path: "hello/lib/hello.rb").contents, "class Hello",
                     "#{what}: the module is not the SDK's own template")
    end
  end

  private

  # This repository, committed whole, as github.com/dagger/ruby-sdk would
  # serve it. The engine fetches by the service's own hostname: a binding's
  # alias, or a name set with withHostname, does not resolve for it here.
  def git_server(ws, source = tree(ws))
    commit = "git init --quiet --initial-branch main && git add --all && " \
             "git -c user.name=e2e -c user.email=e2e@dagger.io commit --quiet --no-gpg-sign --message sdk && " \
             "git clone --quiet --bare /repo /srv/ruby-sdk.git"
    development_image(ws).with_directory(path: "/repo", source:)
                         .with_workdir(path: "/repo")
                         .with_exec(args: ["sh", "-c", commit])
                         .with_exposed_port(port: 9418)
                         .as_service(args: %w[git daemon --reuseaddr --export-all --base-path=/srv --listen=0.0.0.0
                                              /srv])
  end

  # The repository's root at main, in the explicit form, which takes any host:
  # the go-style form, the address a user installs, needs a host with a dot
  # that it looks up over HTTPS.
  def installed_by_git_ref(ws, server, decoys)
    config = <<~TOML
      [modules.ruby-sdk]
      source = "git://#{server.hostname}/ruby-sdk.git#main"

      [sdks.ruby]
      module = "ruby-sdk"
    TOML
    ground = development_image(ws).with_file(path: "/usr/local/bin/dagger", source: ws.file(path: "/#{CLI_PATH}"))
                                  .with_service_binding(alias_: "git-server", service: server)
                                  .with_new_file(path: "#{INSTALLED}/dagger.toml", contents: config)
    ground = decoys.reduce(ground) { |g, (path, contents)| g.with_new_file(path: "#{INSTALLED}/#{path}", contents:) }
    ground = ground.with_workdir(path: INSTALLED).with_exec(args: %w[git init --quiet])
    [%w[module init ruby -y --name hello --path hello], %w[generate -y]].reduce(ground) do |container, args|
      container.with_exec(args: ["dagger", *args], experimental_privileged_nesting: true)
    end
  end
end
