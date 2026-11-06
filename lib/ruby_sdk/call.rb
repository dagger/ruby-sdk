require "fileutils"
require_relative "../ruby_sdk"

# One call from ruby-sdk.dang: the request on stdin, objects by ID, the
# result as JSON in the file named by the argument.
class RubySdk
  module Call
    Core = Dagger::Clients::Core

    module_function

    def run(request)
      Dagger::Mod.module_source_id = request.fetch("moduleSource")
      sdk = RubySdk.new(template: request.fetch("template"), ruby_version: request.fetch("rubyVersion"),
                        target_version: request.fetch("targetVersion"))
      args = JSON.parse(request.fetch("args"))
      case request.fetch("function")
      when "findClientRoot" then sdk.find_client_root(ws: load(Core::Workspace, args.fetch("ws")))
      when "steep" then sdk.steep(ws: load(Core::Workspace, args.fetch("ws")), path: args["path"])
      when "generateScope"
        clients = args.fetch("clients").map { load(Core::ModuleSource, it) }
        sdk.generate_scope(ws: load(Core::Workspace, args.fetch("ws")), is_module: args.fetch("isModule"),
                           name: args.fetch("name"), clients:).id
      else raise Error, "ruby-sdk.dang calls no function #{request["function"].inspect}"
      end
    end

    def load(type, id) = type.new(Dagger::QueryBuilder.new.node(id, type.graphql_name))
  end
end

if $PROGRAM_NAME == __FILE__
  Dagger.mark_module_runtime!
  begin
    result = JSON.generate(RubySdk::Call.run(JSON.parse($stdin.read)))
    FileUtils.mkdir_p(File.dirname(ARGV.fetch(0)))
    File.write(ARGV.fetch(0), result)
  rescue Dagger::Mod::Error, Dagger::QueryError => e
    warn "ruby-sdk: #{e.class}: #{e.message}"
    warn e.stderr if e.is_a?(Dagger::ExecError) && !e.stderr.to_s.empty?
    exit 2
  end
end
