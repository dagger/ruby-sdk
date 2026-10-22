require "json"
require "tmpdir"

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ruby_sdk/codegen/cli"

module CodegenHelper
  CORE_SCHEMA = File.expand_path("../fixtures/core-schema.json", __dir__)
  GOLDEN = File.expand_path("../golden/codegen", __dir__)
  GOLDEN_FILES = %w[
    lib/dagger/clients/core/env_variable.rb sig/dagger/clients/core/env_variable.rbs
    lib/dagger/clients/core/image_layer_compression.rb sig/dagger/clients/core/image_layer_compression.rbs
    lib/dagger/clients/core/build_arg.rb sig/dagger/clients/core/build_arg.rbs
    lib/dagger/clients/core/syncer.rb sig/dagger/clients/core/syncer.rbs
    lib/dagger/clients/core/json.rb sig/dagger/clients/core/json.rbs
    lib/dagger/clients/core/stat.rb sig/dagger/clients/core/stat.rbs
    sig/dagger/clients/core.rbs .dagger-generated
  ].freeze

  CLIENT_GOLDEN_FILES = %w[
    lib/dagger/clients/greeter.rb lib/dagger/clients/greeter/target.rb lib/dagger/clients/greeter/greeter.rb
    lib/dagger/clients/greeter/mood.rb sig/dagger/clients/greeter.rbs sig/dagger/clients/greeter/greeter.rbs
    dagger-clients-greeter.gemspec .dagger-generated
  ].freeze

  ROOTS_GOLDEN_FILES = %w[
    lib/dagger/clients/roots.rb sig/dagger/clients/roots.rbs dagger-clients-roots.gemspec .dagger-generated
  ].freeze

  module_function

  def source_map(module_name)
    { "name" => "sourceMap", "args" => [{ "name" => "module", "value" => module_name.dump }] }
  end

  def non_null(ref) = { "kind" => "NON_NULL", "ofType" => ref }

  def named(kind, name) = { "kind" => kind, "name" => name }

  def field(name, type, module_name, args: [], directives: [])
    { "name" => name, "description" => "", "args" => args, "type" => type, "isDeprecated" => false,
      "directives" => [source_map(module_name), *directives] }
  end

  def arg(name, type, default: nil, directives: [])
    { "name" => name, "description" => "", "type" => type, "defaultValue" => default, "directives" => directives }
  end

  # Core and the module "greeter", as the engine serves a client's schema.
  def client_document(module_name = "greeter")
    document = core_document
    types = document["__schema"]["types"]
    types << mood_type(module_name) << greeter_type(module_name)
    query = types.find { it["name"] == "Query" }
    args = [arg("greeting", named("SCALAR", "String")), arg("session", named("SCALAR", "String"))]
    query["fields"] << field(module_name, non_null(named("OBJECT", "Greeter")), module_name, args:)
    directory = types.find { it["name"] == "Directory" }
    directory["fields"] << field("asGreeter", non_null(named("OBJECT", "Greeter")), module_name)
    document
  end

  def mood_type(module_name)
    { "kind" => "ENUM", "name" => "Mood", "description" => "A mood.", "directives" => [source_map(module_name)],
      "enumValues" => [{ "name" => "HAPPY", "description" => "", "directives" => [] }] }
  end

  def greeter_type(module_name)
    expected = { "name" => "expectedType", "args" => [{ "name" => "name", "value" => '"Directory"' }] }
    { "kind" => "OBJECT", "name" => "Greeter", "description" => "Greets.", "interfaces" => [named("INTERFACE", "Node")],
      "directives" => [source_map(module_name)],
      "fields" => [
        field("id", non_null(named("SCALAR", "ID")), module_name),
        field("greet", non_null(named("SCALAR", "String")), module_name,
              args: [arg("name", named("SCALAR", "String"), default: '"world"')]),
        field("container", non_null(named("OBJECT", "Container")), module_name),
        field("withSource", non_null(named("OBJECT", "Greeter")), module_name,
              args: [arg("source", non_null(named("SCALAR", "ID")), directives: [expected])]),
        field("mood", named("ENUM", "Mood"), module_name)
      ] }
  end

  def client_files
    @client_files ||= RubySdk::Codegen::ClientPackage.files(RubySdk::Codegen::Schema.new(client_document),
                                                            name: "greeter", ref: "/.dagger/modules/greeter")
  end

  def roots_files
    @roots_files ||= RubySdk::Codegen::Roots.files([[RubySdk::Codegen::Schema.new(client_document), "greeter"]])
  end

  def core_document = RubySdk::Codegen::Partition.core_only(JSON.parse(File.read(CORE_SCHEMA)))

  def core_schema = RubySdk::Codegen::Schema.new(core_document)

  def core_files = @core_files ||= RubySdk::Codegen::Package.core(core_schema)
end
