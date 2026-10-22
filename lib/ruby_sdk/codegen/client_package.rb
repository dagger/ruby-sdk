class RubySdk
  module Codegen
    # The files of one client's member: its module's types, its entry point,
    # the fields it adds to core types, and its descriptor.
    module ClientPackage
      module_function

      Contributed = Data.define(:parent, :field)

      # A client's files hold no scope path, so one client is the same bytes
      # in every scope.
      def files(schema, name:, ref:, pin: nil, core_digest: nil)
        Partition.check_attribution(schema)
        digest = Partition.core_digest(schema)
        if core_digest && core_digest != digest
          raise Error, %(the module "#{name}" serves core #{digest}, but the scope's core is #{core_digest})
        end

        file = Naming.client_file(name)
        module_name = find_module(schema, file)
        constant = Naming.client_constant(name)
        render = Render.new(schema, "Dagger::Clients::#{constant}", owner: module_name)
        types = schema.types.values.select { Partition.owner(it) == module_name }.sort_by { it["name"] }
        entry, contributed = entry_and_contributed(schema, module_name, file)
        files = Package.type_files(render, types, "dagger/clients/#{file}")
        files["lib/dagger/clients/#{file}.rb"] = client_index(render, file, types, entry, contributed)
        files["lib/dagger/clients/#{file}/target.rb"] =
          target(render, name: module_name, ref:, pin:, digest:)
        files["sig/dagger/clients/#{file}.rbs"] =
          "#{Render::HEADER}\n#{render.nest(client_index_rbs(render, entry, contributed))}"
        files["dagger-clients-#{file}.gemspec"] =
          Package.gemspec("dagger-clients-#{file}", "Bindings of the Dagger module #{module_name}",
                          ["dagger-clients-core"])
        files[".dagger-generated"] = "client"
        files
      end

      def find_module(schema, file)
        modules = schema.types.values.flat_map { [it, *(it["fields"] || [])] }.filter_map { Schema.source_module(it) }
        modules.uniq.find { Naming.client_file(it) == file } or
          raise Error, %(the schema attributes nothing to the client "#{file}"; it has: #{modules.uniq.join(", ")})
      end

      # The entry is the Query field the module contributes under its own
      # name: the constructor the engine makes for it.
      def entry_and_contributed(schema, module_name, file)
        fields = Partition.core_types(schema).sort_by { it["name"] }.flat_map do |type|
          (type["fields"] || []).select { Schema.source_module(it) == module_name }.map { Contributed.new(type, it) }
        end
        entry = fields.find do |contributed|
          contributed.parent["name"] == "Query" && contributed.field["name"].downcase == file.delete("_")
        end
        raise Error, %(the schema has no constructor for the client "#{module_name}") unless entry

        [entry, fields - [entry]]
      end

      def client_index(render, file, types, entry, contributed)
        autoloads = types.map do |type|
          "autoload :#{render.const(type)}, #{"dagger/clients/#{file}/#{Naming.file_name(type["name"])}".dump}\n"
        end
        functions = [render.entry_function(entry.field)] +
                    contributed.map { render.contributed_function(it.parent, it.field) }
        body = "# Before any core type loads: a core that lacks one must fail as stale, not as missing.\n" \
               "::Dagger::Client.check_core(NAME, CORE_DIGEST, ::Dagger::Clients::Core::CORE_DIGEST)\n\n" \
               "TARGET = ::Dagger::Client::Target.new(name: NAME, ref: REF, pin: PIN)\n\n" \
               "#{autoloads.join}\n#{functions.join("\n")}"
        "#{Render::HEADER}\nrequire \"dagger\"\nrequire \"dagger/clients/core\"\n" \
          "require \"dagger/clients/#{file}/target\"\n\n#{render.nest(body)}"
      end

      def client_index_rbs(render, entry, contributed)
        functions = [render.entry_function_rbs(entry.field)] +
                    contributed.map { render.contributed_function_rbs(it.parent, it.field) }
        "NAME: ::String\nREF: ::String\nPIN: ::String?\nCORE_DIGEST: ::String\nTARGET: ::Dagger::Client::Target\n\n" \
          "#{functions.map { "#{it}\n" }.join}"
      end

      # Plain data, so reading the descriptor never needs the SDK.
      def target(render, name:, ref:, pin:, digest:)
        body = "NAME = #{name.dump}.freeze\nREF = #{ref.dump}.freeze\nPIN = #{pin ? "#{pin.dump}.freeze" : "nil"}\n" \
               "CORE_DIGEST = #{digest.dump}.freeze\n"
        "#{Render::HEADER}\n#{render.nest(body)}"
      end
    end
  end
end
