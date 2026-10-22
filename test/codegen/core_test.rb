require_relative "../test_helper"
require_relative "codegen_helper"
require "English"

class CoreTest < Minitest::Test
  include CodegenHelper

  Partition = RubySdk::Codegen::Partition
  Schema = RubySdk::Codegen::Schema

  def test_the_stand_in_is_removed
    schema = core_schema

    refute schema.types.key?("CoreSchema")
    refute(schema["Query"]["fields"].any? { it["name"] == "coreSchema" })
    assert(schema["Query"]["fields"].any? { it["name"] == "container" })
  end

  def test_a_schema_without_the_stand_in_is_refused
    document = core_document

    assert_raises(RubySdk::Codegen::Error) { Partition.core_only(document) }
  end

  def test_the_core_digest_ignores_clients_and_member_order
    document = core_document
    digest = Partition.core_digest(Schema.new(document))
    with_client = add_client(core_document)
    shuffled = core_document.tap do |shuffle|
      shuffle["__schema"]["types"].reverse!
      shuffle["__schema"]["types"].each { it["fields"]&.reverse! }
    end

    assert_match(/\Asha256:\h{64}\z/, digest)
    assert_equal digest, Partition.core_digest(Schema.new(with_client))
    assert_equal digest, Partition.core_digest(Schema.new(shuffled))
  end

  def test_the_core_digest_changes_with_core
    document = core_document
    digest = Partition.core_digest(Schema.new(document))
    document["__schema"]["types"].find { it["name"] == "Container" }["fields"].pop

    refute_equal digest, Partition.core_digest(Schema.new(document))
  end

  def test_a_client_member_on_a_type_it_cannot_own_is_refused
    document = core_document
    enum = document["__schema"]["types"].find { it["name"] == "ImageLayerCompression" }
    enum["enumValues"].first["directives"] = [source_map("greeter")]

    error = assert_raises(RubySdk::Codegen::Error) { Partition.check_attribution(Schema.new(document)) }
    assert_match(/only a field of a core object or interface type can be contributed/, error.message)
  end

  def test_every_generated_method_takes_keyword_arguments_only
    signatures = core_files.select { |path, _| path.end_with?(".rb") }.values.join.scan(/^\s*def (\w+[?!]?)\((.*)\)/)

    refute_empty signatures
    signatures.each do |name, params|
      next if name == "initialize"

      params.split(", ").each { assert_match(/\A\w+:( nil)?\z/, it, "#{name}(#{params})") }
    end
  end

  def test_no_generated_method_replaces_one_every_object_needs
    defined = core_files.values.join.scan(/^\s*def (\w+[?!]?)/).flatten

    assert_includes defined, "send_"
    refute_empty defined & %w[end module]
    assert_empty defined & RubySdk::Codegen::Naming::RESERVED_METHODS
  end

  # Inside Dagger::Clients::Core, File, JSON, Module and Error are core's types,
  # so every other constant is written from the top level.
  def test_generated_code_names_only_its_own_constants_unqualified
    own = core_files.select { |path, _| path.start_with?("lib/") }.values.join
    defined = own.scan(/^\s*(?:class|module) (\w+)|^\s*(\w+) = /).flatten.compact.uniq + ["Client"]
    code = own.lines.reject { it.strip.start_with?("#") }.join.gsub(/"(?:[^"\\]|\\.)*"/, '""')
    unqualified = code.scan(/(?<![:\w])([A-Z]\w*)/).flatten.uniq - defined

    assert_empty unqualified
  end

  def test_a_nullable_object_result_is_nil_or_an_object
    container = core_files.fetch("lib/dagger/clients/core/container.rb")
    signature = core_files.fetch("sig/dagger/clients/core/container.rbs")

    assert_includes container,
                    '@query.select("stat", path:, doNotFollowSymlinks: do_not_follow_symlinks).execute_optional(Stat)'
    assert_match(/def stat: \(path: ::String, \?do_not_follow_symlinks: bool\?\) -> Stat\?$/, signature)
    assert_includes container, 'Directory.new(@query.select("directory", path:'
    assert_match(/def directory: \(path: ::String.*\) -> Directory$/, signature)
  end

  # @reevaluate: every use evaluates the field again; with when:, only a call
  # that sets one of those arguments.
  def test_an_object_built_through_a_reevaluated_field_is_marked
    address = core_files.fetch("lib/dagger/clients/core/address.rb")
    host = core_files.fetch("lib/dagger/clients/core/host.rb")

    assert_includes address, 'Container.new(@query.select("container", noLock: no_lock).reevaluate)'
    assert_includes address, "noCache: no_cache, noLock: no_lock).reevaluate_when(no_cache, no_lock))"
    assert_includes host, 'File.new(@query.select("file", path:, noCache: no_cache).reevaluate_when(no_cache))'
    assert_includes core_files.fetch("lib/dagger/clients/core/container.rb"),
                    'Container.new(@query.select("withExec", args:'
    refute_match(/withExec.*reevaluate/, core_files.fetch("lib/dagger/clients/core/container.rb"))
  end

  def test_the_package_has_a_marker_a_gemspec_and_an_index
    assert_equal "core", core_files.fetch(".dagger-generated")
    assert_match(/spec.name = "dagger-clients-core"/, core_files.fetch("dagger-clients-core.gemspec"))
    assert_match(/CORE_DIGEST = "sha256:\h{64}".freeze/, core_files.fetch("lib/dagger/clients/core.rb"))
    assert_match(%r{autoload :Container, "dagger/clients/core/container"},
                 core_files.fetch("lib/dagger/clients/core.rb"))
  end

  def test_golden_files
    GOLDEN_FILES.each do |path|
      assert_equal File.read(File.join(GOLDEN, path)), core_files.fetch(path), path
    end
  end

  def test_the_generated_core_loads_and_builds_queries
    Dir.mktmpdir do |dir|
      RubySdk::Codegen::Package.write(core_files, dir)
      script = <<~RUBY
        require "dagger"
        require "dagger/clients/core"
        core = Dagger::Clients::Core
        core.constants.each { core.const_get(it) }
        query = core.core.container.from(address: "alpine").with_exec(args: ["echo", "hi"]).query
        print query.document.lines.map(&:strip).join(" ")
        raise unless core::ImageLayerCompression::GZIP.equal?(core::ImageLayerCompression::Gzip)
        raise unless Dagger::QueryBuilder.literal(core::BuildArg.new(name: "a", value: "b")) == '{name: "a", value: "b"}'
      RUBY
      sdk = File.expand_path("../../sdk/lib", __dir__)
      output = IO.popen(["ruby", "-I", sdk, "-I", "#{dir}/lib", "-e", script], err: %i[child out], &:read)

      assert_predicate $CHILD_STATUS, :success?, output
      assert_equal 'query { container { from(address: "alpine") { withExec(args: ["echo", "hi"]) } } }', output
    end
  end

  private

  def source_map(module_name)
    { "name" => "sourceMap", "args" => [{ "name" => "module", "value" => module_name.dump }] }
  end

  def add_client(document)
    types = document["__schema"]["types"]
    types << { "kind" => "OBJECT", "name" => "Greeter", "description" => "", "interfaces" => [], "possibleTypes" => [],
               "directives" => [source_map("greeter")], "fields" => [] }
    query = types.find { it["name"] == "Query" }
    query["fields"] << { "name" => "greeter", "args" => [], "directives" => [source_map("greeter")],
                         "type" => { "kind" => "NON_NULL", "ofType" => { "kind" => "OBJECT", "name" => "Greeter" } } }
    document
  end
end
