require "digest"
require "json"

class RubySdk
  module Codegen
    # Which types and fields of a schema are core, and which a client owns,
    # by the module that @sourceMap attributes them to.
    module Partition
      STAND_IN = "core-schema".freeze

      module_function

      # The stand-in module's own types and fields, and the ID scalar and
      # loader that older views name after each of its types.
      def core_only(document)
        schema = document["__schema"] || document.dig("data", "__schema")
        gone = schema["types"].select { Schema.source_module(it) == STAND_IN }.map { it["name"] }
        raise Error, "the schema has no type of the module #{STAND_IN}" if gone.empty?

        gone += gone.map { "#{it}ID" }
        schema["types"] = schema["types"].reject { gone.include?(it["name"]) }.map { without_stand_in(it, gone) }
        document
      end

      def without_stand_in(type, gone)
        loaders = gone.map { "load#{it}FromID" }
        type.merge(
          "fields" => type["fields"]&.reject { Schema.source_module(it) == STAND_IN || loaders.include?(it["name"]) },
          "interfaces" => type["interfaces"]&.reject { gone.include?(it["name"]) },
          "possibleTypes" => type["possibleTypes"]&.reject { gone.include?(it["name"]) }
        )
      end

      def owner(type) = Schema.source_module(type)

      def core_types(schema) = schema.types.values.reject { owner(it) }

      def own_fields(type)
        fields = type["fields"] || []
        owner(type) ? fields : fields.reject { Schema.source_module(it) }
      end

      # Refuse a member attributed to a module that cannot own it: a client
      # contributes fields to core object and interface types, and nothing else.
      def check_attribution(schema)
        schema.types.each_value do |type|
          type_owner = owner(type)
          members(type).each do |member|
            module_name = Schema.source_module(member)
            next if module_name.nil? || module_name == type_owner
            next if type_owner.nil? && %w[OBJECT INTERFACE].include?(type["kind"])

            raise Error, attribution_message(type, member, module_name, type_owner)
          end
        end
      end

      def members(type) = (type["fields"] || []) + (type["inputFields"] || []) + (type["enumValues"] || [])

      def attribution_message(type, member, module_name, type_owner)
        place = %("#{type["name"]}.#{member["name"]}" is attributed to the client "#{module_name}")
        if type_owner
          %(#{place}, but its type "#{type["name"]}" is attributed to the client "#{type_owner}")
        else
          "#{place}, but only a field of a core object or interface type can be contributed"
        end
      end

      # Members go by name: the order the engine lists them in is not part of
      # the API, and must not make a client look stale.
      def core_digest(schema)
        digest = Digest::SHA256.new
        core_types(schema).sort_by { it["name"] }.each do |type|
          next if schema.builtin_scalar?(type["name"])

          digest << JSON.generate(describe(type)) << "\n"
        end
        "sha256:#{digest.hexdigest}"
      end

      def describe(type)
        {
          "kind" => type["kind"], "name" => type["name"], "description" => type["description"],
          "directives" => type["directives"] || [],
          "interfaces" => (type["interfaces"] || []).map { it["name"] }.sort,
          "fields" => own_fields(type).sort_by { it["name"] }.map { describe_field(it) },
          "inputFields" => (type["inputFields"] || []).sort_by { it["name"] },
          "enumValues" => (type["enumValues"] || []).sort_by { it["name"] }
        }
      end

      def describe_field(field) = field.merge("args" => (field["args"] || []).sort_by { it["name"] })
    end
  end
end
