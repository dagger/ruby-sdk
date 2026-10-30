class E2E
  CALLER_FILE = "only-in-the-caller.txt".freeze

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
    require "json"
    require "dagger"
    require "dagger/clients/roots"

    class EpCaller
      extend Dagger::Mod::Object
      include Dagger::Clients::Roots

      function "The target's greeting, through its client by the long form."
      #: (build: String) -> String
      def greeting(build:) = "\#{build}: \#{Dagger::Clients::EpTarget.ep_target.greeting}"

      function "The target's greeting, through the client's method in the client roots."
      #: (build: String) -> String
      def short_greeting(build:) = "\#{build}: \#{ep_target.greeting} on \#{core.version}"

      function "What the module runs from, after a client call: the entries of its source, and its files on disk."
      #: (build: String) -> String
      def own_files(build:)
        Dagger::Clients::EpTarget.ep_target.greeting
        pattern = "**/{ep_caller.rb,#{CALLER_FILE}}"
        files = Dir.glob(pattern, base: File.expand_path("..", __dir__), flags: File::FNM_DOTMATCH)
        JSON.generate(build:, source: Dagger::Mod.module_source.entries, files:)
      end

      function "A file of the caller's workspace, through a declared Workspace argument."
      #: (ws: Dagger::Clients::Core::Workspace, build: String) -> String
      def declared(ws:, build:) = "\#{build}: \#{ws.file(path: #{"/#{CALLER_FILE}".dump}).contents}"
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
           "dagger module init to dagger call; it runs from its own source, which holds none of the caller's " \
           "files, and a declared Workspace argument reaches them.", check: true
  #: (ws: Core::Workspace) -> void
  def entrypoint_client_call_check(ws:)
    ws = fixtures(ws)
    target = ".dagger/modules/ep-target"
    caller = ".dagger/modules/ep-caller"
    ground = playground(ws).with_new_file(path: "#{PLAYGROUND}/#{target}/lib/ep_target.rb", contents: EP_TARGET)
    ground = cli(ground, "module", "init", "ruby", "-y", "--name", "ep-target", "--path", target)
    ground = cli(ground, "module", "init", "ruby", "-y", "--name", "ep-caller", "--path", caller)
             .with_new_file(path: "#{PLAYGROUND}/#{caller}/lib/ep_caller.rb", contents: EP_CALLER)
    ground = cli(ground, "module", "client", "add", "../ep-target", "--sdk", "ruby", "-y", workdir: caller)
    check(file_in(ground, "#{caller}/dagger-module.toml") == manifest("ep-caller"),
          "the caller is not on its entrypoint")

    build = ["--build", core.version]
    called = cli(ground, "-m", caller, "call", "greeting", *build).stdout
    check_includes(called, "hello from the target", "the module did not call its client")
    short = cli(ground, "-m", caller, "call", "short-greeting", *build).stdout
    check_includes(short, "hello from the target on #{core.version}", "the module did not call its client's method")

    contents = "only in the caller's workspace"
    ground = ground.with_new_file(path: "#{PLAYGROUND}/#{CALLER_FILE}", contents:)
    own = JSON.parse(cli(ground, "-m", caller, "call", "own-files", *build).stdout)
    # Each list must also name the module's own files, or its lack of the
    # caller's file would prove nothing.
    check_includes(own["source"], "dagger-module.toml", "Dagger::Mod.module_source is not the module's own directory")
    check_includes(own["source"], "lib/", "Dagger::Mod.module_source is not the module's own directory")
    check_excludes(own["source"], CALLER_FILE, "Dagger::Mod.module_source holds the caller's file")
    check(own["files"] == ["lib/ep_caller.rb"], "the module's files on disk are #{own["files"]}")
    declared = cli(ground, "-m", caller, "call", "declared", *build).stdout
    check_includes(declared, contents, "a declared Workspace argument did not reach the caller's workspace")
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
