require_relative "../test_helper"
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__),
                   File.expand_path("../../tmp/codegen/core/lib", __dir__)
require "ruby_sdk/scope"

# A workspace in memory: paths from its root to contents, immutable like the
# engine's, so a test sees exactly what generation wrote.
class FakeTree
  attr_reader :files

  def initialize(files) = @files = files.freeze

  def exists(path:) = files.key?(path) || files.keys.any? { it.start_with?("#{path.delete_suffix("/")}/") }

  def file(path:) = FakeFile.new(files.fetch(path) { raise "no file #{path}" })

  def directory(path:, **)
    prefix = "#{path.delete_suffix("/")}/"
    FakeTree.new(files.filter_map { |p, c| [p.delete_prefix(prefix), c] if p.start_with?(prefix) }.to_h)
  end

  def entries
    files.keys.map { it.include?("/") ? "#{it.split("/").first}/" : it }.uniq.sort
  end

  def filter(**) = self

  def glob(pattern:) = files.keys.select { File.fnmatch?(pattern, it, File::FNM_PATHNAME) }.sort

  def with_new_file(path:, contents:) = FakeTree.new(files.merge(path => contents))
end

FakeFile = Data.define(:contents)

FakeRef = Data.define(:commit)
FakeGit = Data.define(:head)

class FakeWorkspace
  attr_reader :tree, :cwd, :address

  def initialize(tree, cwd, address: "", commit: nil)
    @tree = tree
    @cwd = cwd
    @address = address
    @commit = commit
  end

  def git
    raise Dagger::QueryError.new([{ "message" => "not in a git repository" }], nil) unless @commit

    FakeGit.new(FakeRef.new(@commit))
  end

  def directory(path:, **) = path == "/" ? tree : tree.directory(path: path.delete_prefix("/"))

  def with_workdir(path:) = copy(cwd: path == "." ? "/" : "/#{path}")

  def find_up(name:, from: nil)
    dir = File.join(cwd.delete_prefix("/"), from.to_s).delete_prefix("/").delete_suffix("/").delete_prefix("./")
    dir = "" if dir == "."
    loop do
      candidate = dir.empty? ? name : "#{dir}/#{name}"
      return "/#{candidate}" if tree.files.key?(candidate)
      return nil if dir.empty?

      dir = dir.include?("/") ? File.dirname(dir) : ""
    end
  end

  def find_roots(markers:, **) = tree.files.keys.select { markers.include?(File.basename(it)) }.map { File.dirname(it) }

  def with_new_file(path:, contents:) = write(path, contents)

  def with_file(path:, source:) = write(path, source.contents)

  def with_new_directory(path:, source:)
    cleared = without_directory(path:)
    source.files.reduce(cleared) { |ws, (rel, contents)| ws.write("#{path}/#{rel}", contents) }
  end

  def without_directory(path:)
    prefix = "#{path.delete_prefix("/")}/"
    copy(tree: FakeTree.new(tree.files.reject { |p, _| p.start_with?(prefix) }))
  end

  def write(path, contents) = copy(tree: FakeTree.new(tree.files.merge(path.delete_prefix("/") => contents)))

  private

  def copy(tree: @tree, cwd: @cwd) = FakeWorkspace.new(tree, cwd, address:, commit: @commit)
end

FakeClient = Data.define(:module_name, :kind, :as_string, :pin, :source_root_subpath, :clone_ref)

# Scope with the engine's work replaced: members come out as marked trees.
class OfflineScope < RubySdk::Scope
  private

  def core_member
    FakeTree.new(".dagger-generated" => "core", "lib/dagger/clients/core.rb" => 'CORE_DIGEST = "sha256:c"')
  end

  def client_member(member, _digest) = FakeTree.new(".dagger-generated" => "client", "ref" => member.ref)

  def bundled(_existing, target, _members) = target

  def with_entrypoint(target, _members)
    target.with_new_file(path: at("dagger-module.toml"), contents: RubySdk::Manifest.render(@name))
  end

  def sdk_tree = FakeTree.new(".dagger-generated" => "sdk", "lib/dagger.rb" => "")

  def written(target, members)
    target = target.with_new_directory(path: at("sdk"), source: sdk_tree)
    target = target.with_new_directory(path: at("clients/core"), source: core_member)
    members.each { target = target.with_new_directory(path: at("clients/#{it.dir}"), source: client_member(it, "")) }
    target.with_new_file(path: at("dagger.gemfile"), contents: dagger_gemfile(members))
  end
end
