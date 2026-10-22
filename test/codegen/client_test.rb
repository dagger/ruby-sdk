require_relative "../test_helper"
require_relative "codegen_helper"

class ClientTest < Minitest::Test
  include CodegenHelper

  GOLDEN_CLIENT = File.expand_path("../golden/codegen-client", __dir__)
  Package = RubySdk::Codegen::Package
  ClientPackage = RubySdk::Codegen::ClientPackage
  Schema = RubySdk::Codegen::Schema

  def test_golden_files
    CLIENT_GOLDEN_FILES.each do |path|
      assert_equal File.read(File.join(GOLDEN_CLIENT, path)), client_files.fetch(path), path
    end
  end

  def test_the_descriptor_names_the_module_and_its_address
    target = client_files.fetch("lib/dagger/clients/greeter/target.rb")

    assert_includes target, 'NAME = "greeter".freeze'
    assert_includes target, 'REF = "/.dagger/modules/greeter".freeze'
    assert_includes target, "PIN = nil"
    assert_includes target, %(CORE_DIGEST = "#{RubySdk::Codegen::Partition.core_digest(core_schema)}".freeze)
  end

  def test_a_git_client_records_its_pin
    files = ClientPackage.files(Schema.new(client_document), name: "greeter", ref: "github.com/acme/greeter@v1",
                                                             pin: "0123abc")

    assert_includes files.fetch("lib/dagger/clients/greeter/target.rb"), 'PIN = "0123abc".freeze'
  end

  def test_core_is_checked_before_any_core_type_is_named
    index = client_files.fetch("lib/dagger/clients/greeter.rb")
    check = index.index("::Dagger::Client.check_core(NAME, CORE_DIGEST, ::Dagger::Clients::Core::CORE_DIGEST)")

    assert check
    assert_operator check, :<, index.index("autoload")
  end

  def test_core_types_are_named_from_the_top_level
    greeter = client_files.fetch("lib/dagger/clients/greeter/greeter.rb")

    assert_includes greeter, "include ::Dagger::Clients::Core::Node"
    assert_includes greeter, "::Dagger::Clients::Core::Container.new(@query.select(\"container\"))"
    assert_includes greeter, "Mood.from_name(it)"
  end

  def test_the_entry_point_and_a_contributed_field
    index = client_files.fetch("lib/dagger/clients/greeter.rb")

    assert_includes index, "def self.greeter(greeting: nil, session_: nil, session: nil)"
    assert_includes index, '::Dagger::Client.root(TARGET, "greeter", { greeting:, session: session_ }, session:)'
    assert_includes index, "def self.as_greeter(directory)"
    assert_includes index, '::Dagger::Client.select(directory, TARGET, "asGreeter", {})'
  end

  def test_a_client_is_the_same_bytes_in_two_directories
    trees = Array.new(2) do
      Dir.mktmpdir do |dir|
        Package.write(ClientPackage.files(Schema.new(client_document), name: "greeter", ref: "/m/greeter"), dir)
        Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).sort.to_h do |path|
          [path, File.file?("#{dir}/#{path}") && File.read("#{dir}/#{path}")]
        end
      end
    end

    assert_equal trees.first, trees.last
  end

  def test_client_names_that_cannot_be_packages_are_refused
    assert_equal "my_dep", RubySdk::Codegen::Naming.client_file("My-Dep")
    assert_equal "MyDep", RubySdk::Codegen::Naming.client_constant("my.dep")
    %w[core CORE 3d a-b!].each do |name|
      assert_raises(RubySdk::Codegen::Error, name) { RubySdk::Codegen::Naming.client_file(name) }
    end
    assert_raises(RubySdk::Codegen::Error) { RubySdk::Codegen::Naming.client_files(%w[my-dep my.dep]) }
  end

  def test_a_client_that_names_another_clients_type_is_refused
    document = client_document
    other = { "kind" => "OBJECT", "name" => "Other", "description" => "", "interfaces" => [],
              "directives" => [source_map("other")], "fields" => [] }
    document["__schema"]["types"] << other
    document["__schema"]["types"].find { it["name"] == "Greeter" }["fields"] <<
      field("other", non_null(named("OBJECT", "Other")), "greeter")

    error = assert_raises(RubySdk::Codegen::Error) do
      ClientPackage.files(Schema.new(document), name: "greeter", ref: "/x")
    end
    assert_match(/names "Other" of the client "other"/, error.message)
  end

  def test_a_client_for_another_core_than_the_scopes_is_refused
    error = assert_raises(RubySdk::Codegen::Error) do
      ClientPackage.files(Schema.new(client_document), name: "greeter", ref: "/x", core_digest: "sha256:other")
    end
    assert_match(/serves core sha256:\h+, but the scope's core is sha256:other/, error.message)
  end

  def test_a_name_the_schema_does_not_have_is_refused
    schema = Schema.new(client_document)

    assert_raises(RubySdk::Codegen::Error) { ClientPackage.files(schema, name: "nope", ref: "/x") }
  end
end
