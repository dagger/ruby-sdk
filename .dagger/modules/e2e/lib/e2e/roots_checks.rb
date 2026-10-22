class E2E
  CLASHES = {
    "the field dep has the name of" => "field :dep #: String",
    "the function core has the name of" => %(function "Core."\n#: () -> String\ndef core = ""),
    "the constructor argument dep has the name of" =>
      "constructor\n#: (dep: String) -> instance\ndef self.create(dep:) = new",
    "App#dep hides" => "private def dep = nil"
  }.freeze
  REFUSED_CLIENTS = { "tap" => "which every Ruby object has (Kernel#tap)", "begin" => "which is a Ruby keyword" }.freeze

  function "Generation refuses a field, function, constructor argument or method of a class that includes the " \
           "client roots with the name of a client method, and a client whose method a keyword or every Ruby " \
           "object has, naming both.", check: true
  #: (ws: Core::Workspace) -> void
  def client_method_clash_check(ws:)
    client = ws.module_source(path: "/#{DEP}")
    source = ws.file(path: "/#{APP}/lib/app.rb").contents
    CLASHES.each do |clash, declaration|
      included = "  extend Dagger::Mod::Object\n  include Dagger::Clients::Roots\n#{declaration.gsub(/^/, "  ")}\n"
      rooted = source.sub(%(require "dagger"\n), %(require "dagger"\nrequire "dagger/clients/roots"\n))
                     .sub("  extend Dagger::Mod::Object\n", included)
      seeded = ws.with_new_file(path: "/#{APP}/lib/app.rb", contents: rooted)
      error = refusal { generate(seeded, APP, name: "app", clients: [client]) }
      check(error.to_s.include?("#{clash} the method") && error.include?("Dagger::Clients::Roots gives the client "),
            "#{declaration.inspect} was not refused: #{error.inspect}")
    end
    REFUSED_CLIENTS.each do |name, why|
      scope = "#{OUT}/client-#{name}"
      made = generate(ws.with_new_directory(path: "/#{scope}", source: core.directory), scope, name:)
      error = refusal { generate(made, APP, name: "app", clients: [made.module_source(path: "/#{scope}")]) }
      check_includes(error.to_s, %(the client "#{name}" would get the method #{name}, #{why}),
                     "a client #{name} was not refused")
    end
  end
end
