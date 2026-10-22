# What module code can read of its caller's files: nothing.
#
# Copied into a module that runs on its generated entrypoint. Reach takes every
# ID module code holds without asking its caller, whatever the SDK's session
# keeps and its own current workspace, and drives each down every route on a
# ModuleSource (and a Module, and a Workspace) that could rebuild a directory
# from somewhere other than the source's own loaded files: the caller's host,
# its currentWorkspace, or a workspace the source secretly retained.
#
# Each route reads a file that exists only at the caller's workspace root and
# is never in the module's files. A route that returns it is a finding. A route
# that fails reassures only if the capability was refused, not if the field
# does not exist on this engine: the two are told apart, and the summary
# reports the split, so a run that proved nothing cannot read as a pass.
class Reach
  # A climb reaches the caller's root only when the number of "../" lands
  # exactly on it, and the module's depth is not known here.
  DEPTHS = (1..12)
  MUTATIONS = [%w[withName name reach], %w[withSDK source] + [""], %w[withEngineVersion version v1.0.0-0]].freeze

  def initialize(secret)
    @secret = secret
    @query = Dagger::QueryBuilder.new
  end

  def report
    held = [*held_ids, own_workspace_id]
    sources = held + held.flat_map { sub_source_ids(@query.node(it, "ModuleSource")) }
    counts = Hash.new(0)
    reads = []
    absent = []
    routes = sources.flat_map { all_routes(it) } + [["currentWorkspace.directory", file(own_root, @secret)]]
    routes.each do |label, query|
      status, detail = probe(query)
      counts[status] += 1
      reads << "#{label}: #{detail}" if status == :read
      absent << label if status == :absent
    end
    "held=#{held.size} sources=#{sources.size} routes=#{routes.size} reads=#{reads} " \
      "refused=#{counts[:refused]} absent=#{counts[:absent]} empty=#{counts[:empty]} " \
      "errored=#{counts[:errored]} absentRoutes=[#{absent.uniq.sort.join(",")}]"
  end

  private

  # Every ID-shaped string the SDK's session holds, however it holds it.
  def held_ids
    found = []
    walk = lambda do |value, depth|
      next if depth > 4

      case value
      when String then found << value if value.size > 20
      when Hash then value.each_value { walk.call(it, depth + 1) }
      when Array, Struct then value.to_a.each { walk.call(it, depth + 1) }
      else value.instance_variables.each { walk.call(value.instance_variable_get(it), depth + 1) }
      end
    end
    walk.call(Dagger.default_session, 0)
    found
  end

  def own_workspace_id = @query.select("currentWorkspace").select("id").execute

  def own_root = @query.select("currentWorkspace").select("directory", path: "/")

  def ups = DEPTHS.map { "../" * it }

  def file(directory, path) = directory.select("file", path:).select("contents")

  # A plain read, in case a reload already pulled the file in at the root,
  # and a climb at each depth, by path and by stepping up first.
  def read_dir(directory)
    routes = [["file", file(directory, @secret)]]
    ups.each do |up|
      routes << ["file(../x#{up.count("/")})", file(directory, up + @secret)]
      routes << ["directory(../x#{up.count("/")}).file", file(directory.select("directory", path: up), @secret)]
    end
    routes
  end

  # Directory routes on a ModuleSource: every field that rebuilds or exposes
  # a context. Scalars, schema JSON, generate(workspace:), which needs the
  # very capability in question, and the client and dependency mutations,
  # which leave the context root alone, are left out, as Python's probe does.
  def source_dirs(source)
    dirs = [["contextDirectory", source.select("contextDirectory")]] + climbs(source)
    dirs << ["generatedContextDirectory", source.select("generatedContextDirectory")]
    dirs << ["updatedConfigDirectory", source.select("updatedConfigDirectory")]
    dirs << ["generatedContextChangeset.layer", source.select("generatedContextChangeset").select("layer")]
    MUTATIONS.each do |field, arg, value|
      dirs << ["#{field}.contextDirectory", source.select(field, arg.to_sym => value).select("contextDirectory")]
    end
    dirs.flat_map { |label, dir| read_dir(dir).map { |how, query| ["#{label} #{how}", query] } }
  end

  # withIncludes an escaping pattern reloads the context from wherever the
  # source came from; withSourceSubpath and directory climb the same way.
  # Each depth is its own route: the engine refuses a whole pattern list if
  # any pattern escapes.
  def climbs(source)
    ups.flat_map do |up|
      n = up.count("/")
      [["withIncludes(../x#{n}).contextDirectory",
        source.select("withIncludes", patterns: [up + @secret]).select("contextDirectory")],
       ["withSourceSubpath(../x#{n}).contextDirectory",
        source.select("withSourceSubpath", path: up).select("contextDirectory")],
       ["directory(../x#{n})", source.select("directory", path: up)]]
    end
  end

  # One level down: the source's dependencies and its own asModule.source.
  def sub_source_ids(source)
    ids = []
    begin
      ids += source.select("dependencies").select("id").execute(allow_nil: true).to_a.map { it["id"] }
    rescue Dagger::Error
      nil
    end
    begin
      id = source.select("asModule").select("source").select("id").execute(allow_nil: true)
      ids << id if id
    rescue Dagger::Error
      nil
    end
    ids
  end

  def all_routes(held)
    workspace = @query.node(held, "Workspace")
    routes = [["workspace.file", workspace.select("file", path: "/#{@secret}").select("contents")],
              ["workspace.directory", file(workspace.select("directory", path: "/"), @secret)]]
    routes += source_dirs(@query.node(held, "ModuleSource")).map { |label, query| ["source #{label}", query] }
    module_source = @query.node(held, "Module").select("source")
    routes + source_dirs(module_source).map { |label, query| ["module.source #{label}", query] }
  end

  # The field does not exist on this engine: a validation error, before any
  # resolver runs. Anything else means a resolver ran and refused.
  def absent?(error)
    error.errors.any? { it["path"].nil? && it.dig("extensions", "code") == "GRAPHQL_VALIDATION_FAILED" }
  end

  def probe(query)
    value = query.execute(allow_nil: true)
    value.nil? ? [:empty, ""] : [:read, value.strip]
  rescue Dagger::QueryError => e
    [absent?(e) ? :absent : :refused, e.message[0, 120]]
  rescue StandardError => e
    [:errored, e.message[0, 120]]
  end
end
