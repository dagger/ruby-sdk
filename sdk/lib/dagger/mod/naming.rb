module Dagger
  module Mod
    module Naming
      module_function

      # The engine's rule for a module's main object, strcase.ToCamel of
      # github.com/iancoleman/strcase v0.3.0.
      def to_camel(name)
        cap_next = true
        prev_cap = false
        name.strip.each_char.with_index.each_with_object(+"") do |(char, index), out|
          cap = char.match?(/[A-Z]/)
          if cap_next then char = char.upcase
          elsif index.zero? || (prev_cap && cap) then char = char.downcase
          end
          prev_cap = cap
          if char.match?(/[A-Za-z]/)
            out << char
            cap_next = false
          elsif char.match?(/[0-9]/)
            out << char
            cap_next = true
          else
            cap_next = ["_", " ", "-", "."].include?(char)
          end
        end
      end

      def snake(name)
        name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      end

      def api_name(ruby_name)
        head, *rest = ruby_name.to_s.split("_")
        [head, *rest.map(&:capitalize)].join
      end

      def file_name(module_name)
        snake(module_name.gsub(/[^A-Za-z0-9]+/, "_")).squeeze("_").delete_prefix("_").delete_suffix("_")
      end

      def module_file(module_name) = "lib/#{file_name(module_name)}.rb"
    end
  end
end
