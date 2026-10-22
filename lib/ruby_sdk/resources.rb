require "prism"
require_relative "error"

class RubySdk
  # What a module's build reads outside its directory, found in its Gemfile
  # and the files the Gemfile evaluates: the directories of path gems and
  # gemspecs, and the files of eval_gemfile and ruby file:. The entrypoint's
  # sources returns them for the engine to load with the module.
  class Resources
    # Paths are relative to the module's directory, cleaned.
    Found = Data.define(:path, :directory, :at)

    EXCLUDED = %w[.bundle vendor/bundle].freeze

    # read: the contents of a file of the workspace by its path relative to
    # the module's directory, or nil. depth: how many directories the module
    # sits below the workspace's root.
    def initialize(read, depth)
      @read = read
      @depth = depth
    end

    def found
      @found ||= begin
        found = {} #: Hash[String, Found]
        visit("Gemfile", ".", found, {})
        found.values.sort_by(&:path)
      end
    end

    # The directories outside, each once: one inside another goes.
    def directories
      all = found.select(&:directory).map(&:path)
      all.reject { |dir| all.any? { dir != it && dir.start_with?("#{it}/") } }
    end

    # The files outside not in one of the directories.
    def files = found.reject(&:directory).map(&:path).reject { |file| directories.any? { file.start_with?("#{it}/") } }

    # What the module's context holds outside its directory, as include and
    # ! exclude patterns: each directory whole but for Bundler's own, then
    # each file.
    def patterns = (directories + files).sort + directories.flat_map { |dir| EXCLUDED.map { "!#{dir}/#{it}" } }.sort

    # Whether the lock's path gem at remote, relative to the module, is one
    # of the directories found.
    def covers?(remote)
      path = self.class.clean(remote)
      !self.class.outside?(path) || directories.any? { path == it || path.start_with?("#{it}/") }
    end

    def self.clean(path)
      parts = path.split("/").each_with_object([]) do |part, kept|
        next if part.empty? || part == "."

        part == ".." && !kept.empty? && kept.last != ".." ? kept.pop : kept << part
      end
      parts.empty? ? "." : parts.join("/")
    end

    def self.outside?(path) = path == ".." || path.start_with?("../")

    private

    def visit(file, dir, found, seen)
      return if seen[file]

      seen[file] = true
      source = @read.call(file) or return
      calls(Prism.parse(source).value) { |call| declared(call, file, dir, found, seen) }
    end

    def calls(node, &)
      yield node if node.is_a?(Prism::CallNode) && node.receiver.nil?
      node.compact_child_nodes.each { calls(it, &) }
    end

    def declared(call, file, dir, found, seen)
      at = "#{file}:#{call.location.start_line}"
      case call.name
      when :gem, :gemspec then keyword(call, :path, at) { add(dir, it, true, at, found) }
      when :path then positional(call, "path", at) { add(dir, it, true, at, found) }
      when :ruby then keyword(call, :file, at) { add(dir, it, false, at, found) }
      when :eval_gemfile
        positional(call, "eval_gemfile", at) do |path|
          evaluated = add(dir, path, false, at, found)
          visit(evaluated, File.dirname(evaluated), found, seen)
        end
      end
    end

    def keyword(call, name, at)
      hash = call.arguments&.arguments&.last
      return unless hash.is_a?(Prism::KeywordHashNode)

      hash.elements.each do |element|
        next unless element.is_a?(Prism::AssocNode)

        key = element.key
        yield literal(element.value, "#{name}:", at) if key.is_a?(Prism::SymbolNode) && key.unescaped == name.to_s
      end
    end

    def positional(call, what, at)
      value = call.arguments&.arguments&.first or return
      yield literal(value, what, at) unless value.is_a?(Prism::KeywordHashNode)
    end

    def literal(node, what, at)
      return node.unescaped if node.is_a?(Prism::StringNode)

      raise Error, "#{at}: #{what} is not a string literal; generation reads it to load what the module needs " \
                   "outside its directory, so write the path itself"
    end

    # The path, relative to the module's directory; recorded when outside.
    def add(dir, path, directory, at, found)
      if path.start_with?("/", "~")
        raise Error, "#{at}: #{path.dump} is absolute; name what the module needs outside its directory by a path " \
                     "relative to the file that names it"
      end
      cleaned = self.class.clean("#{dir}/#{path}")
      return cleaned unless self.class.outside?(cleaned)

      check_outside(cleaned, at)
      found[cleaned] ||= Found.new(cleaned, directory, at)
      cleaned
    end

    def check_outside(path, at)
      ups = path.split("/").take_while { it == ".." }.size
      if ups > @depth
        raise Error, "#{at}: #{path.dump} leaves the workspace's root, which holds every file the engine loads with " \
                     "the module"
      end
      return unless path.split("/").all?("..")

      raise Error, "#{at}: #{path.dump} holds the module itself; name the directory of what it needs"
    end
  end
end
