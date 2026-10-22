require_relative "error"

class RubySdk
  module Codegen
    module Naming
      KEYWORDS = %w[
        __ENCODING__ __LINE__ __FILE__ BEGIN END alias and begin break case class def defined? do else elsif end
        ensure false for if in module next nil not or redo rescue retry return self super then true undef unless
        until when while yield
      ].freeze
      # Methods every object needs, which a generated method must not replace,
      # and the reader that holds each object's query.
      RESERVED_METHODS = %w[class send object_id hash method freeze dup clone then tap display query].freeze

      module_function

      def snake(name)
        name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      end

      def method_name(graphql_name)
        name = snake(graphql_name)
        RESERVED_METHODS.include?(name) ? "#{name}_" : name
      end

      def argument_name(graphql_name)
        name = snake(graphql_name)
        KEYWORDS.include?(name) ? "#{name}_" : name
      end

      def constant(name)
        raise Error, "#{name.inspect} cannot be a Ruby constant" unless name.match?(/\A[A-Z]\w*\z/)

        name
      end

      def file_name(type_name) = snake(type_name)

      # A client name becomes its gem's directory and file, and its constant.
      def client_file(name)
        file = name.downcase.tr("-.", "__")
        unless file.match?(/\A[a-z_]\w*\z/)
          raise Error, %(client name "#{name}" becomes "#{file}", which is not a Ruby name)
        end
        raise Error, %(client name "#{name}" is taken by the core bindings) if file == "core"
        raise Error, %(client name "#{name}" is taken by the scope's client roots) if file == "roots"

        file
      end

      def client_constant(name) = client_file(name).split("_").map(&:capitalize).join

      def client_files(names)
        taken = {} #: Hash[String, String]
        names.each do |name|
          file = client_file(name)
          if (other = taken.key(file))
            raise Error, %(clients "#{other}" and "#{name}" both become "#{file}")
          end

          taken[name] = file
        end
        taken
      end
    end
  end
end
