require "fileutils"
require "json"
require_relative "schema"
require_relative "naming"
require_relative "partition"
require_relative "render"
require_relative "package"
require_relative "client_package"
require_relative "roots"

class RubySdk
  module Codegen
    # Runs in an exec the SDK module starts, with the schemas mounted as files
    # and the member written to a directory the engine reads back.
    module CLI
      USAGE = "usage: cli.rb core <stand-in-schema.json> <out> | " \
              "client <schema.json> <out> <name> <ref> <core-digest> [<pin>] | " \
              "roots <out> [<schema.json> <name>]...".freeze

      module_function

      def run(argv)
        command, *args = argv
        case command
        when "core" then core(args)
        when "client" then client(args)
        when "roots" then roots(args)
        else raise Error, USAGE
        end
      end

      def core(args)
        schema_path, out = args
        raise Error, USAGE unless schema_path && out

        Package.write(Package.core(Schema.new(Partition.core_only(read(schema_path)))), out)
      end

      def client(args)
        schema_path, out, name, ref, core_digest, pin = args
        raise Error, USAGE unless schema_path && out && name && ref && core_digest

        Package.write(ClientPackage.files(Schema.new(read(schema_path)), name:, ref:, pin:, core_digest:), out)
      end

      def roots(args)
        out, *pairs = args
        raise Error, USAGE unless out && pairs.size.even?

        clients = pairs.each_slice(2).map do |path, name|
          [Schema.new(read(path.to_s)), name.to_s] #: [Schema, String]
        end
        Package.write(Roots.files(clients), out)
      end

      def read(path) = JSON.parse(::File.read(path))
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    RubySdk::Codegen::CLI.run(ARGV)
  rescue RubySdk::Codegen::Error => e
    abort "codegen: #{e.message}"
  end
end
