class E2E
  # What the checks share: assertions, the SDK module through its client,
  # and the playground, a container where the CLI runs on this tree.
  module Support
    Core = Dagger::Clients::Core
    FIXTURES = ".dagger/modules/e2e/fixtures".freeze
    OUT = ".dagger/modules/e2e/out".freeze
    CLI_PATH = ".dagger/modules/e2e/cli/dagger".freeze
    PLAYGROUND = "/work/ruby-sdk".freeze
    APP = "#{FIXTURES}/app".freeze
    DEP = "#{FIXTURES}/clients/dep".freeze
    PLAIN = "#{FIXTURES}/plain".freeze
    LOOKUP = "#{FIXTURES}/lookup/app".freeze
    CONFIG_APP = "#{FIXTURES}/config/app".freeze
    CONFIGURED = "#{FIXTURES}/config/configured".freeze
    EXCLUDED = [".git", "**/vendor/bundle", "**/.bundle", OUT, ".dagger/modules/e2e/cli"].freeze
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

    def development_image(ws)
      ws.directory(path: "/", include: ["hack/dev.Dockerfile", "hack/tools/**"])
        .docker_build(dockerfile: "hack/dev.Dockerfile")
    end

    # The CLI built with the engine under test, as a nested client of it, in
    # a git checkout of this tree, so that addresses resolve as on a
    # developer's machine.
    def playground(ws, files = tree(ws))
      unless ws.directory(path: "/").exists(path: CLI_PATH)
        raise Failure, "the playground needs the dev CLI at #{CLI_PATH}, which hack/e2e.sh copies"
      end

      development_image(ws).with_file(path: "/usr/local/bin/dagger", source: ws.file(path: "/#{CLI_PATH}"))
                           .with_directory(path: PLAYGROUND, source: files)
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
