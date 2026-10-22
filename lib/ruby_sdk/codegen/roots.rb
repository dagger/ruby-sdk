class RubySdk
  module Codegen
    # The member clients/roots: one module, Dagger::Clients::Roots, whose
    # private methods are core and the scope's clients, each named and typed as
    # its entry point, so that a class that includes it writes core.container
    # or lib(...) for a client lib.
    module Roots
      NAMESPACE = "Dagger::Clients::Roots".freeze

      Root = Data.define(:client, :name, :ruby, :rbs, :file)

      CORE = Root.new("core", "core", "def core(session: nil) = ::Dagger::Clients::Core.core(session:)\n",
                      "def core: (?session: ::Dagger::Session?) -> ::Dagger::Clients::Core::Query", "core")

      module_function

      # clients: [schema, name] for each client of the scope.
      def files(clients)
        roots = [CORE, *clients.map { |schema, name| root(schema, name) }]
        check(roots)
        {
          "lib/dagger/clients/roots.rb" => ruby(roots),
          "sig/dagger/clients/roots.rbs" => "#{Render::HEADER}\n#{Package.nest(NAMESPACE, rbs(roots))}",
          "dagger-clients-roots.gemspec" =>
            Package.gemspec("dagger-clients-roots", "The scope's clients as methods", ["dagger-clients-core"]),
          ".dagger-generated" => "roots"
        }
      end

      # A client's method is its entry point's name, in snake case: the
      # engine's constructor field for the module, so p11lib gives p11_lib.
      def method_name(field_name) = Naming.snake(field_name)

      def root(schema, name)
        file = Naming.client_file(name)
        module_name = ClientPackage.find_module(schema, file)
        entry, = ClientPackage.entry_and_contributed(schema, module_name, file)
        render = Render.new(schema, "Dagger::Clients::#{Naming.client_constant(name)}", owner: module_name,
                                                                                        qualified: true)
        method = method_name(entry.field["name"])
        rbs = render.entry_function_rbs(entry.field).sub(/\Adef self\.\w+:/, "def #{method}:")
        Root.new(name, method, render.root_function(entry.field, method), rbs, file)
      end

      # A method that a keyword, core or every Ruby object already has would
      # hide it, or never be callable; two clients cannot share one.
      def check(roots)
        roots.drop(1).each do |root|
          why = refusal(root.name) or next
          raise Error, %(the client "#{root.client}" would get the method #{root.name}, which #{why})
        end
        roots.group_by(&:name).each_value do |same|
          next if same.size == 1

          raise Error, %(the clients #{same.map { it.client.dump }.join(" and ")} would both get the method ) +
                       same.first.name
        end
      end

      def refusal(method)
        if method == "core" then "is core's"
        elsif Naming::KEYWORDS.include?(method) then "is a Ruby keyword"
        elsif ::Object.method_defined?(method) || ::Object.private_method_defined?(method)
          "every Ruby object has (#{::Object.instance_method(method).owner}##{method})"
        end
      end

      def ruby(roots)
        requires = ["dagger", *roots.map { "dagger/clients/#{it.file}" }].map { "require #{it.dump}\n" }.join
        clients = roots.map { "#{it.name}: #{it.client.dump}" }.join(", ")
        body = "# The client each method stands for.\ndef self.clients = { #{clients} }.freeze\n\nprivate\n\n" \
               "#{roots.map(&:ruby).join("\n")}"
        "#{Render::HEADER}\n#{requires}\n#{Package.nest(NAMESPACE, body)}"
      end

      def rbs(roots)
        "def self.clients: () -> ::Hash[::Symbol, ::String]\n\nprivate\n\n#{roots.map { "#{it.rbs}\n" }.join}"
      end
    end
  end
end
