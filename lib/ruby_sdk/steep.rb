require "perfect_toml"
require_relative "error"
require_relative "manifest"
require_relative "scope"
require_relative "signatures"

class RubySdk
  # Steep over the Ruby modules this SDK generated in a workspace, behind
  # what dagger generate refuses of each. A module is found by what
  # generation writes into it, through the Workspace API: its manifest names
  # the generated entrypoint, sdk/ carries the SDK's marker, and it has a
  # Gemfile.
  #
  # Steep sees a def without an annotation as untyped and a field without
  # one as an untyped call, and reports neither. So each module first goes
  # through generation's own refusals (Scope's class methods): its scope's
  # members and manifest, Bundler on its Gemfile, and dagger-mod entrypoint
  # on its annotations as they are now. Steep then checks it against the
  # module.rbs that writes, in the module's image with its Gemfile's
  # development group installed, which the module's container skips.
  class Steep
    Core = ::Dagger::Clients::Core
    COMMAND = %w[bundle exec steep check].freeze
    PRUNED = ["**/vendor/bundle/**", "**/.bundle/**", "**/node_modules/**"].freeze

    # refusals: what dagger generate refuses of the module, each in its own
    # words; steep: whether Steep ran, which needs a Steepfile.
    Outcome = Data.define(:root, :refusals, :steep, :exit_code, :output)

    class Outcome
      def failed? = !refusals.empty? || !exit_code.zero?
    end

    def initialize(ws:, image:)
      @ws = ws
      @root_ws = ws.with_workdir(path: ".")
      @image = image
    end

    # Every module, or the one at or above path. Passing, it says that
    # dagger generate accepts every module checked, and Steep every one with
    # a Steepfile.
    def check(path = nil)
      roots = path ? [module_at(path)] : modules
      outcomes = roots.map { |root| Thread.new { outcome(root) } }.map(&:value)
      failed = outcomes.select(&:failed?)
      summary = self.class.summary(outcomes)
      raise Error, "#{self.class.failure(failed, roots.size)}\n\n#{summary}" unless failed.empty?

      warn "ruby-sdk: #{summary}"
    end

    def modules
      @root_ws.find_roots(markers: [Manifest::FILE], exclude: PRUNED).map { self.class.normalize(it) }
              .select { authored?(it) }.sort
    end

    # The nearest module at or above path, which resolves from the
    # workspace's cwd.
    def module_at(path)
      found = @ws.find_up(name: Manifest::FILE, from: path) or
        raise Error, "no module at or above #{path}: no #{Manifest::FILE} there or above"
      root = self.class.normalize(::File.dirname(found))
      return root if authored?(root)

      raise Error, "#{root} is a module, but not a Ruby module this SDK generated"
    end

    def authored?(root)
      dir = directory(root)
      dir.exists(path: "Gemfile") && Scope.kind(dir, "sdk") == "sdk" &&
        Manifest.entrypoint?(dir.file(path: Manifest::FILE).contents)
    end

    def self.normalize(path)
      trimmed = path.delete_prefix("/").delete_prefix("./").delete_suffix("/")
      trimmed.empty? ? "." : trimmed
    end

    def self.failure(failed, count)
      blocks = failed.flat_map do |outcome|
        refusals = outcome.refusals.map { "#{outcome.root}: dagger generate refuses it\n#{it}" }
        steep = "#{outcome.root}: #{COMMAND.join(" ")} exited #{outcome.exit_code}\n#{outcome.output.rstrip}"
        refusals + (outcome.exit_code.zero? ? [] : [steep])
      end
      "The Steep check failed in #{failed.size} of #{count} Ruby modules: #{failed.map(&:root).join(", ")}\n\n" \
        "#{blocks.join("\n\n")}"
    end

    def self.summary(outcomes)
      list = ->(selected) { selected.empty? ? "none" : selected.map(&:root).join(", ") }
      skipped = outcomes.reject(&:steep)
      lines = ["checked: #{list.call(outcomes)}",
               "generation checks ok: #{list.call(outcomes.select { it.refusals.empty? })}",
               "steep ok: #{list.call(outcomes.select { it.steep && it.exit_code.zero? })}"]
      lines << "steep skipped, no Steepfile: #{list.call(skipped)}" unless skipped.empty?
      lines.join("\n")
    end

    private

    def directory(root) = @root_ws.directory(path: root == "." ? "/" : "/#{root}")

    def outcome(root)
      dir = directory(root)
      client_dirs = client_dirs(dir)
      name = PerfectTOML.parse(dir.file(path: Manifest::FILE).contents).fetch("name", "").to_s
      resources, resources_refusal = resources_of(root)
      build = Scope.build_for(dir, @image, name, client_dirs, resources:, path: root)
      source, subpath = build.context? && resources ? [Scope.context(@root_ws, root, dir, resources), root] : [dir, nil]
      refusals = [scope_refusal(root, dir, client_dirs), resources_refusal,
                  Scope.bundler_refusal(root, Scope.bundler(build, source, false, client_dirs, subpath:)),
                  lock_refusal(root, dir, resources)].compact
      checked(root, dir, build, refusals, [source, subpath])
    end

    # The members and manifest checks of generation, which read files only.
    def scope_refusal(root, dir, client_dirs)
      Scope.check_members(root, dir, client_dirs)
      Scope.check_manifest(root, dir)
      nil
    rescue Error => e
      e.message
    end

    # What the module reads outside its directory, as generation finds it,
    # and the engine able to load it; or what generation refuses of either.
    def resources_of(root)
      resources = Scope.resources(@root_ws, root)
      Scope.check_resources_engine(root, resources)
      [resources, nil]
    rescue Error => e
      [nil, e.message]
    end

    def lock_refusal(root, dir, resources)
      return nil unless resources && dir.exists(path: "Gemfile.lock")

      Scope.lock_refusal(root, dir.file(path: "Gemfile.lock").contents, resources)
    end

    # dagger-mod entrypoint as generation runs it, then Steep on the
    # module.rbs it writes, or on the committed one when it refuses. A failed
    # install is reported as Steep's.
    def checked(root, dir, build, refusals, layout)
      source, subpath = layout
      installed = Core::Container.new(build.installed(Core.core.query, source, development: true, subpath:))
      described = Scope.describe(installed, dir, subpath:)
      refused = Scope.describe_refusal(root, described)
      all = refusals + [refused].compact
      return Outcome.new(root, all, false, 0, "") unless dir.exists(path: "Steepfile")

      steeped = refused ? installed : with_module_rbs(installed, described, subpath)
      ran = steeped.with_exec(args: COMMAND, expect: Core::ReturnType::ANY)
      Outcome.new(root, all, true, ran.exit_code, ran.combined_output)
    rescue ::Dagger::ExecError => e
      failed = "#{Array(e.command).join(" ")} failed\n#{e.stdout}#{e.stderr}"
      Outcome.new(root, refusals, true, e.exit_code || 1, failed)
    end

    def with_module_rbs(installed, described, subpath)
      rbs = described.file(path: "/dagger/entrypoint/module.rbs")
      installed.with_file(path: "#{subpath ? "/src/#{subpath}" : "/src"}/sdk/entrypoint/module.rbs", source: rbs)
    end

    # The clients generation last wrote, which are the scope's members.
    def client_dirs(dir)
      return [] unless dir.exists(path: "clients")

      dir.directory(path: "clients").entries.map { it.delete_suffix("/") }.reject { %w[core roots].include?(it) }
         .select { Scope.kind(dir, "clients/#{it}") == "client" }.sort
    end
  end
end
