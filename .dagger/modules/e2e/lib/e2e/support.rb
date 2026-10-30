class E2E
  # What the checks share: assertions, the SDK module through its client,
  # and the playground, a container where the CLI runs on this tree.
  module Support
    Core = Dagger::Clients::Core
    FIXTURES = ".dagger/modules/e2e/fixtures".freeze
    OUT = ".dagger/modules/e2e/out".freeze
    PLAYGROUND = "/work/ruby-sdk".freeze
    APP = "#{FIXTURES}/app".freeze
    DEP = "#{FIXTURES}/clients/dep".freeze
    PLAIN = "#{FIXTURES}/plain".freeze
    LOOKUP = "#{FIXTURES}/lookup/app".freeze
    CONFIG_APP = "#{FIXTURES}/config/app".freeze
    CONFIGURED = "#{FIXTURES}/config/configured".freeze
    # The fixture scopes, which the repository keeps as sources: path => what
    # dagger.toml would record. A client comes before the scopes that use it.
    SCOPES = {
      APP => { name: "app" },
      DEP => { name: "dep" },
      LOOKUP => { name: "lookup-app" },
      "#{FIXTURES}/types" => { name: "types", clients: [DEP] },
      PLAIN => { clients: [DEP] },
      CONFIG_APP => { name: "config-app" },
      CONFIGURED => { name: "config-configured", ruby_version: "3.4" },
      "#{FIXTURES}/collections/app" => { name: "collections" },
      "#{FIXTURES}/collections/caller" => { name: "collections-caller", clients: ["#{FIXTURES}/collections/app"] },
      "#{FIXTURES}/include/app" => { name: "include-app" },
      "#{FIXTURES}/include/caller" => { name: "include-caller", clients: ["#{FIXTURES}/include/app"] }
    }.freeze
    EXCLUDED = [".git", "**/vendor/bundle", "**/.bundle", OUT].freeze
    EVAL_LINE = %(eval_gemfile "dagger.gemfile").freeze

    class Failure < StandardError; end

    def check(condition, message)
      raise Failure, message unless condition
    end

    def check_includes(value, want, message) = check(value.include?(want), "#{message}: #{value.inspect}")

    def check_excludes(value, unwanted, message) = check(!value.include?(unwanted), "#{message}: #{value.inspect}")

    def core = Core.core

    def sdk(template: nil, ruby_version: nil) = Dagger::Clients::RubySdk.ruby_sdk(template:, ruby_version:)

    def generate(ws, scope, is_module: true, name: "", clients: [], with: sdk)
      with.generate_scope(ws: ws.with_workdir(path: scope), is_module:, name:, clients:)
    end

    # A refusal reaches the caller as the failed exec of the SDK module's
    # call, its message in stderr; nil if generation went through.
    def refusal
      yield.cwd
      nil
    rescue Dagger::ExecError => e
      "#{e.message}\n#{e.stderr}"
    rescue Dagger::QueryError => e
      e.message
    end

    # By content: a directory's digest also covers its entries' metadata.
    def same_files?(left, right) = left.changes(from: right).is_empty

    # Both sides from the root, so that paths are the workspace's.
    def changed(after, before) = after.with_workdir(path: ".").changes(from: before.with_workdir(path: "."))

    def manifest(name) = %(name = "#{name}"\n\n[entrypoint]\nkind = "dang"\nsource = "./sdk/entrypoint"\n)

    def paths(changes)
      "added #{changes.added_paths}, modified #{changes.modified_paths}, removed #{changes.removed_paths}"
    end

    def core_digest(scope)
      scope.file(path: "clients/core/lib/dagger/clients/core.rb").contents[/CORE_DIGEST = "([^"]+)"/, 1]
    end

    def with_function(source, function)
      source.sub(/\nend\n\z/, "\n\n#{function.gsub(/^(?=.)/, "  ")}end\n")
    end

    def tree(ws) = ws.directory(path: "/", exclude: EXCLUDED)

    # The workspace with the fixture scopes registered in dagger.toml and
    # generated, as dagger generate would leave them. A workspace of a
    # directory, so that a client among the fixtures loads what was generated
    # here: a workspace of a git ref resolves one at its commit, which holds
    # the fixtures' sources only.
    def fixtures(ws)
      config = "#{ws.file(path: "/dagger.toml").contents}\n#{scopes_config}"
      registered = tree(ws).with_new_file(path: "dagger.toml", contents: config).as_workspace
      SCOPES.reduce(registered) do |generated, (path, scope)|
        clients = scope.fetch(:clients, []).map { generated.module_source(path: "/#{it}") }
        generate(generated, path, is_module: scope.key?(:name), name: scope.fetch(:name, ""), clients:,
                                  with: sdk(ruby_version: scope[:ruby_version]))
      end.with_workdir(path: ".")
    end

    def scopes_config
      SCOPES.map do |path, scope|
        lines = [%([sdks.ruby.scopes."#{path}"])]
        lines.push("is-module = true", %(name = "#{scope[:name]}")) if scope[:name]
        lines << "clients = [#{scope[:clients].map { %("./#{it}") }.join(", ")}]" if scope[:clients]
        lines.push("", %([sdks.ruby.scopes."#{path}".settings]), %(rubyVersion = "#{scope[:ruby_version]}")) \
          if scope[:ruby_version]
        "#{lines.join("\n")}\n"
      end.join("\n")
    end

    def development_image(ws)
      ws.directory(path: "/", include: ["hack/dev.Dockerfile", "hack/tools/**"])
        .docker_build(dockerfile: "hack/dev.Dockerfile")
    end

    # The engine's own CLI, which a nested exec finds on its PATH, as a
    # nested client of the engine under test, in a git checkout of this tree,
    # so that addresses resolve as on a developer's machine.
    def playground(ws, files = tree(ws))
      development_image(ws).with_directory(path: PLAYGROUND, source: files)
                           .with_workdir(path: PLAYGROUND)
                           .with_exec(args: %w[git init --quiet])
    end

    # A nested CLI resolves -m and relative paths against its exec's
    # working directory, so every call names its own.
    def cli(container, *args, workdir: ".")
      container.with_workdir(path: File.join(PLAYGROUND, workdir))
               .with_exec(args: ["dagger", *args], experimental_privileged_nesting: true)
    end

    def cli_failure(container, *args)
      failed = container.with_workdir(path: PLAYGROUND)
                        .with_exec(args: ["dagger", *args], experimental_privileged_nesting: true,
                                   expect: Core::ReturnType::FAILURE)
      "#{failed.stdout}\n#{failed.stderr}"
    end

    def file_in(container, path) = container.file(path: "#{PLAYGROUND}/#{path}").contents

    def exists_in(container, path) = container.directory(path: PLAYGROUND).exists(path:)
  end
end
