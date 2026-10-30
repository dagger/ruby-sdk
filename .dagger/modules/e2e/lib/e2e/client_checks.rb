class E2E
  SECRET = "review-secret.txt".freeze

  EP_TARGET = <<~RUBY.freeze
    require "dagger"

    class EpTarget
      extend Dagger::Mod::Object

      function "A greeting."
      #: () -> String
      def greeting = "hello from the target"
    end
  RUBY

  EP_CALLER = <<~RUBY.freeze
    require "dagger"
    require "dagger/clients/roots"
    require_relative "reach"

    class EpCaller
      extend Dagger::Mod::Object
      include Dagger::Clients::Roots

      function "The target's greeting, through its client by the long form."
      #: (build: String) -> String
      def greeting(build:) = "\#{build}: \#{Dagger::Clients::EpTarget.ep_target.greeting}"

      function "The target's greeting, through the client's method in the client roots."
      #: (build: String) -> String
      def short_greeting(build:) = "\#{build}: \#{ep_target.greeting} on \#{core.version}"

      function "What this module's code can read of its caller's files."
      #: (build: String) -> String
      def reach(build:)
        Dagger::Clients::EpTarget.ep_target.greeting
        "\#{build}: \#{Reach.new(#{SECRET.dump}).report}"
      end

      function "A file of the caller's workspace, through a declared Workspace argument."
      #: (ws: Dagger::Clients::Core::Workspace, build: String) -> String
      def declared(ws:, build:) = "\#{build}: \#{ws.file(path: #{"/#{SECRET}".dump}).contents}"
    end
  RUBY

  # The leaf reads a file of its module, so its target changes without
  # dagger generate; every value carries its own fresh part, so equal values
  # mean a cache hit.
  CACHE_MODULES = {
    "cache-leaf" => <<~RUBY,
      require "dagger"
      require "securerandom"

      class CacheLeaf
        extend Dagger::Mod::Object

        function "The nonce file and a part new on every run."
        #: () -> String
        def value = "leaf \#{File.read(File.expand_path("../nonce.txt", __dir__)).strip} \#{SecureRandom.hex(4)}"
      end
    RUBY
    "cache-lib" => <<~RUBY,
      require "dagger"
      require "securerandom"
      require "dagger/clients/cache_leaf"

      class CacheLib
        extend Dagger::Mod::Object

        function "The leaf's value and a part new on every run."
        #: () -> String
        def value = "lib \#{SecureRandom.hex(4)} \#{Dagger::Clients::CacheLeaf.cache_leaf.value}"
      end
    RUBY
    "cache-demo" => <<~RUBY
      require "dagger"
      require "securerandom"
      require "dagger/clients/cache_lib"

      class CacheDemo
        extend Dagger::Mod::Object

        function "The lib's value and a part new on every run."
        #: () -> String
        def value = "demo \#{SecureRandom.hex(4)} \#{Dagger::Clients::CacheLib.cache_lib.value}"
      end
    RUBY
  }.freeze

  function "A module on its generated entrypoint calls a local client whose module is on one too, from " \
           "dagger module init to dagger call; its code reads nothing of the caller's workspace, and a " \
           "declared Workspace argument still reaches the caller's file.", check: true
  #: (ws: Core::Workspace) -> void
  def entrypoint_client_call_check(ws:)
    ws = fixtures(ws)
    target = ".dagger/modules/ep-target"
    caller = ".dagger/modules/ep-caller"
    ground = playground(ws).with_new_file(path: "#{PLAYGROUND}/#{target}/lib/ep_target.rb", contents: EP_TARGET)
    ground = cli(ground, "module", "init", "ruby", "-y", "--name", "ep-target", "--path", target)
    ground = cli(ground, "module", "init", "ruby", "-y", "--name", "ep-caller", "--path", caller)
             .with_new_file(path: "#{PLAYGROUND}/#{caller}/lib/ep_caller.rb", contents: EP_CALLER)
             .with_file(path: "#{PLAYGROUND}/#{caller}/lib/reach.rb",
                        source: ws.file(path: "/#{FIXTURES}/reach/reach.rb"))
    ground = cli(ground, "module", "client", "add", "../ep-target", "--sdk", "ruby", "-y", workdir: caller)
    check(file_in(ground, "#{caller}/dagger-module.toml") == manifest("ep-caller"),
          "the caller is not on its entrypoint")

    build = ["--build", core.version]
    called = cli(ground, "-m", caller, "call", "greeting", *build).stdout
    check_includes(called, "hello from the target", "the module did not call its client")
    short = cli(ground, "-m", caller, "call", "short-greeting", *build).stdout
    check_includes(short, "hello from the target on #{core.version}", "the module did not call its client's method")

    secret = "only in the caller's workspace"
    ground = ground.with_new_file(path: "#{PLAYGROUND}/#{SECRET}", contents: secret)
    reached = cli(ground, "-m", caller, "call", "reach", *build).stdout
    check_includes(reached, "reads=[]", "module code read a caller file")
    check_excludes(reached, secret, "module code read a caller file")
    # The probe proves something only if it held an ID to try, ran its
    # routes, and hit no unknown field (fixtures/reach/reach.rb).
    check_excludes(reached, "held=0 ", "the module held nothing to try, so this proves nothing")
    check_includes(reached, "absent=0 ", "a probe route hit an unknown field, so it proves nothing")
    check_excludes(reached, "routes=0 ", "the probe ran no routes")
    declared = cli(ground, "-m", caller, "call", "declared", *build).stdout
    check_includes(declared, secret, "a declared Workspace argument did not reach the caller's workspace")
  end

  function "With the same arguments, an unchanged target hits the cache, and a changed local target returns " \
           "its new value, one hop and two. One line per assertion.", check: true
  #: (ws: Core::Workspace) -> void
  def client_cache_check(ws:)
    ws = fixtures(ws)
    # The check runs only on a cache miss: a fresh nonce keeps the cache
    # modules of an earlier run from answering.
    nonce = SecureRandom.hex(8)
    ground = cache_modules(playground(ws), nonce)
    # Each call is its own exec, so that only the engine's function cache can
    # answer a repeated one.
    value = lambda do |name, call|
      cli(ground.with_env_variable(name: "E2E_CALL", value: call), "-m", ".dagger/modules/#{name}", "call", "value")
        .stdout.strip
    end
    first = value.call("cache-lib", "first")
    lines = [cache_line("unchanged-target-hits-cache", value.call("cache-lib", "again") == first ? nil : "a new value")]
    demo = value.call("cache-demo", "first")
    ground = ground.with_new_file(path: "#{PLAYGROUND}/.dagger/modules/cache-leaf/nonce.txt",
                                  contents: "#{nonce}-changed\n")
    lines << changed_line("changed-target-one-hop", first, value.call("cache-lib", "changed"), nonce)
    lines << changed_line("changed-target-two-hops", demo, value.call("cache-demo", "changed"), nonce)
    lines.each { puts it }
    check(lines.all? { it.end_with?(": ok") }, lines.join("\n"))
  end

  private

  def cache_modules(ground, nonce)
    CACHE_MODULES.each_with_index.reduce(ground) do |built, ((name, source), index)|
      path = ".dagger/modules/#{name}"
      file = "#{PLAYGROUND}/#{path}/lib/#{name.tr("-", "_")}.rb"
      if index.zero?
        written = built.with_new_file(path: file, contents: source)
                       .with_new_file(path: "#{PLAYGROUND}/#{path}/nonce.txt", contents: "#{nonce}\n")
        next cli(written, "module", "init", "ruby", "-y", "--name", name, "--path", path)
      end

      initialized = cli(built, "module", "init", "ruby", "-y", "--name", name, "--path", path)
                    .with_new_file(path: file, contents: source)
      cli(initialized, "module", "client", "add", "../#{CACHE_MODULES.keys[index - 1]}", "--sdk", "ruby", "-y",
          workdir: path)
    end
  end

  def cache_line(name, failure) = "clientCacheCheck #{name}: #{failure ? "FAIL #{failure}" : "ok"}"

  def changed_line(name, before, after, nonce)
    failure = if after == before then "stale, returned the old value"
              elsif !after.include?("#{nonce}-changed") then "returned #{after.inspect}"
              end
    cache_line(name, failure)
  end
end
