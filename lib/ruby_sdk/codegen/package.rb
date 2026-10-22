require "json"

class RubySdk
  module Codegen
    # The files of a generated member, by path inside the member.
    module Package
      CORE = "core".freeze
      VERSION = "0.0.0".freeze

      module_function

      def core(schema)
        Partition.check_attribution(schema)
        namespace = "Dagger::Clients::Core"
        render = Render.new(schema, namespace)
        types = Partition.core_types(schema).select { render.generated?(it["name"]) }.sort_by { it["name"] }
        files = type_files(render, types, "dagger/clients/core")
        files["lib/dagger/clients/core.rb"] = core_index(render, types, Partition.core_digest(schema))
        files["sig/dagger/clients/core.rbs"] = "#{Render::HEADER}\n#{render.nest(core_index_rbs)}"
        files["dagger-clients-core.gemspec"] = gemspec("dagger-clients-core", "Bindings of the Dagger core API")
        files[".dagger-generated"] = CORE
        files
      end

      def type_files(render, types, path)
        files = {} #: Hash[String, String]
        types.each do |type|
          file = Naming.file_name(type["name"])
          raise Error, "two types generate #{path}/#{file}.rb" if files.key?("lib/#{path}/#{file}.rb")

          files["lib/#{path}/#{file}.rb"] = render.ruby(type)
          files["sig/#{path}/#{file}.rbs"] = render.rbs(type)
        end
        files
      end

      def core_index(render, types, digest)
        autoloads = types.map do |type|
          "autoload :#{render.const(type)}, #{"dagger/clients/core/#{Naming.file_name(type["name"])}".dump}\n"
        end
        body = "CORE_DIGEST = #{digest.dump}.freeze\n\n#{autoloads.join}\n" \
               "def self.core(session: nil) = Query.new(::Dagger::QueryBuilder.new(session:))\n"
        "#{Render::HEADER}\nrequire \"dagger\"\n\n#{render.nest(body)}"
      end

      def core_index_rbs
        "CORE_DIGEST: ::String\n\ndef self.core: (?session: ::Dagger::Session?) -> Query\n"
      end

      def nest(namespace, body)
        modules = namespace.split("::")
        opening = modules.each_with_index.map { |name, depth| "#{"  " * depth}module #{name}\n" }.join
        closing = modules.each_index.reverse_each.map { |depth| "#{"  " * depth}end\n" }.join
        indented = body.lines.map { |line| line.strip.empty? ? "\n" : "#{"  " * modules.size}#{line}" }.join
        opening + indented + closing
      end

      def gemspec(name, summary, dependencies = [])
        deps = ["dagger-sdk", *dependencies].map { "  spec.add_dependency #{it.dump}\n" }.join
        <<~RUBY
          #{Render::HEADER}
          Gem::Specification.new do |spec|
            spec.name = #{name.dump}
            spec.version = #{VERSION.dump}
            spec.summary = #{summary.dump}
            spec.authors = ["Dagger"]
            spec.license = "Apache-2.0"
            spec.required_ruby_version = ">= 3.4"
            spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb", "sig/**/*.rbs"] }
            spec.require_paths = ["lib"]
          #{deps.chomp}
          end
        RUBY
      end

      def write(files, out)
        files.sort.each do |path, content|
          target = ::File.join(out, path)
          ::FileUtils.mkdir_p(::File.dirname(target))
          ::File.write(target, content)
        end
      end
    end
  end
end
