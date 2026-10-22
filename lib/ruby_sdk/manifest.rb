require "perfect_toml"

class RubySdk
  # A Ruby module's dagger-module.toml: manifest version 2, with a name and
  # the generated Dang entrypoint, and nothing else.
  module Manifest
    FILE = "dagger-module.toml".freeze
    ENTRYPOINT = "./sdk/entrypoint".freeze

    module_function

    def render(name)
      %(name = #{name.dump}\n\n[entrypoint]\nkind = "dang"\nsource = "#{ENTRYPOINT}"\n)
    end

    # Read with a TOML parser: the manifest is the user's file, and a pattern
    # over its text would misread it.
    def objections(toml)
      manifest = PerfectTOML.parse(toml)
      keys = manifest.keys - %w[name entrypoint]
      keys.delete("source") if %w[. ./].include?(manifest["source"])
      keys.map { objection(it) } + entrypoint_objections(manifest["entrypoint"])
    rescue PerfectTOML::ParseError => e
      ["it is not valid TOML (#{e.message})"]
    end

    def objection(key)
      case key
      when "runtime" then "[runtime]: a Ruby module runs on its generated entrypoint"
      when "dependencies" then "[[dependencies]]: declare a client with `dagger module client add`"
      when "engineVersion" then "engineVersion: an entrypoint runs on the engine's own version"
      when "include", "exclude" then "#{key}: an entrypoint module is its whole directory"
      when "source" then "source: an entrypoint module is rooted at its own directory"
      else "#{key}: manifest version 2 has only name and [entrypoint]"
      end
    end

    # Whether the manifest names the entrypoint this SDK generates, as every
    # module it generated does.
    def entrypoint?(toml)
      entrypoint = PerfectTOML.parse(toml)["entrypoint"]
      !entrypoint.nil? && entrypoint_objections(entrypoint).empty?
    rescue PerfectTOML::ParseError
      false
    end

    def entrypoint_objections(entrypoint)
      return [] if entrypoint.nil?
      return ["[entrypoint] is not a table"] unless entrypoint.is_a?(Hash)

      found = [] #: Array[String]
      unless entrypoint["kind"] == "dang"
        found << "[entrypoint] kind #{entrypoint["kind"].inspect}: the SDK writes \"dang\""
      end
      unless %w[./sdk/entrypoint sdk/entrypoint].include?(entrypoint["source"])
        found << "[entrypoint] source #{entrypoint["source"].inspect}: the SDK generates #{ENTRYPOINT}"
      end
      found
    end
  end
end
