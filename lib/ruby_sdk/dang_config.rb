require "perfect_toml"
require_relative "error"

class RubySdk
  # The dang.toml beside a module's generated entrypoint. The Dang wrapper of
  # generateScope writes it through sdk-helpers; this reads it, for what that
  # write would lose or what would contradict the module's target version.
  module DangConfig
    FILE = "sdk/entrypoint/dang.toml".freeze
    LANGUAGE = "2.1".freeze
    IMPORT = "Dagger".freeze
    # Between the entrypoint and the module's directory, where the engine stops looking.
    SDK_ANCESTOR = "sdk/dang.toml".freeze
    ANCESTORS = [SDK_ANCESTOR, "dang.toml"].freeze

    module_function

    # The engine reads the nearest file alone: a new file hides only the nearest ancestor.
    def check(path, existing, target_version)
      if existing.exists(path: FILE)
        objections = objections(existing.file(path: FILE).contents, target_version)
        return if objections.empty?

        raise Error, "#{path}/#{FILE} has what a module's generated entrypoint cannot carry: #{objections.join("; ")}"
      end
      nearest = ANCESTORS.find { existing.exists(path: it) }
      check_ancestor(path, existing, nearest, target_version) if nearest
    end

    def check_ancestor(path, existing, ancestor, target_version)
      hidden = hidden(existing.file(path: ancestor).contents, target_version)
      return if hidden.empty?

      raise Error, "#{path}/#{ancestor} has what generating #{FILE} would hide: #{hidden.join("; ")}. Generation " \
                   "copies nothing from it, since its relative paths would change: remove what it names, run " \
                   "dagger generate, then set what the module needs in #{FILE}"
    end

    def objections(toml, target_version)
      config = PerfectTOML.parse(toml)
      found = [] #: Array[String]
      unless [nil, LANGUAGE].include?(config["dang"])
        found << "dang = #{config["dang"].inspect}: the generated entrypoint is written in Dang #{LANGUAGE}"
      end
      imports = config["imports"]
      return found if imports.nil?
      return found + ["imports is not a table"] unless imports.is_a?(Hash)

      found + imports.flat_map { |name, import| import_objections(name, import, target_version) }
    rescue PerfectTOML::ParseError => e
      ["it is not valid TOML (#{e.message})"]
    end

    def import_objections(name, import, target_version)
      return ["imports.#{name} is not a table"] unless import.is_a?(Hash)

      if name != IMPORT
        version = import["dagger"]
        return [] if !version.is_a?(String) || version == target_version

        return ["imports.#{name}.dagger = #{version.inspect}: the module's target version is #{target_version}"]
      end
      found = [] #: Array[String]
      found << "imports.#{IMPORT}.path: the SDK sets imports.#{IMPORT}.dagger, which excludes it" if import.key?("path")
      unless ["", nil].include?(import["endpoint"])
        found << "imports.#{IMPORT}.endpoint: Dang allows no endpoint with the version the SDK sets"
      end
      found
    end

    # What an ancestor sets that the generated file would not. A dagger = true
    # is no pin, and the generated file replaces it with the target version.
    def hidden(toml, target_version)
      config = PerfectTOML.parse(toml)
      found = config.keys - %w[imports dang]
      found << "dang" unless [nil, LANGUAGE].include?(config["dang"])
      imports = config["imports"]
      return found if imports.nil?
      return found + ["imports"] unless imports.is_a?(Hash)

      found + imports.reject { |name, import| name == IMPORT && managed_import?(import, target_version) }
                     .keys.map { "imports.#{it}" }
    rescue PerfectTOML::ParseError => e
      ["it is not valid TOML (#{e.message})"]
    end

    def managed_import?(import, target_version)
      import.is_a?(Hash) && import.keys == ["dagger"] && [true, target_version].include?(import["dagger"])
    end
  end
end
