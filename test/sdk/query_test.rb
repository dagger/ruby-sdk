require_relative "../test_helper"
require "dagger"

class QueryTest < Minitest::Test
  class Color < Dagger::Enum
    RED = new("RED", "red")
    CRIMSON = RED
    BAD = new("RED } evil {", "x")
  end

  Label = Data.define(:name, :value, :created_at) do
    include Dagger::Input

    def self.graphql_names = { name: "name", value: "value", created_at: "createdAt" }

    def initialize(name:, value: nil, created_at: nil) = super
  end

  class Thing < Dagger::Type; end

  def literal(value) = Dagger::QueryBuilder.literal(value)

  def test_strings_are_escaped_as_json
    assert_equal '"say \"hi\""', literal('say "hi"')
    assert_equal '"back\\\\slash"', literal("back\\slash")
    assert_equal '"line\nbreak\ttab"', literal("line\nbreak\ttab")
    assert_equal '"héllo ✓"', literal("héllo ✓")
  end

  def test_a_string_that_is_not_valid_utf8_is_refused
    assert_raises(Dagger::InvalidQueryError) { literal((+"\xff").force_encoding("UTF-8")) }
  end

  def test_scalars
    assert_equal "null", literal(nil)
    assert_equal "true", literal(true)
    assert_equal "false", literal(false)
    assert_equal "42", literal(42)
    assert_equal "-1.5", literal(-1.5)
    assert_equal '"{\"a\":1}"', literal(Dagger::Scalar.new('{"a":1}'))
  end

  def test_floats_that_graphql_cannot_carry_are_refused
    assert_raises(Dagger::InvalidQueryError) { literal(Float::NAN) }
    assert_raises(Dagger::InvalidQueryError) { literal(Float::INFINITY) }
  end

  def test_an_enum_goes_by_name_and_aliases_are_one_member
    assert_equal "RED", literal(Color::RED)
    assert_same Color::RED, Color::CRIMSON
    assert_equal [Color::RED, Color::BAD], Color.members
    assert_same Color::RED, Color.from_name("RED")
    assert_raises(Dagger::InvalidQueryError) { Color.from_name("BLUE") }
  end

  def test_an_enum_name_that_is_not_a_name_is_refused
    error = assert_raises(Dagger::InvalidQueryError) { literal(Color::BAD) }

    assert_match(/Invalid enum value name/, error.message)
  end

  def test_an_input_object_renders_its_set_fields_by_graphql_name
    assert_equal '{name: "a", createdAt: 3}', literal(Label.new(name: "a", created_at: 3))
  end

  def test_lists_nest
    assert_equal '[["a", "b"], [], [1]]', literal([%w[a b], [], [1]])
  end

  def test_anything_else_is_refused
    assert_raises(Dagger::InvalidQueryError) { literal({ a: 1 }) }
    assert_raises(Dagger::InvalidQueryError) { literal(:symbol) }
    assert_raises(Dagger::InvalidQueryError) { literal(Object.new) }
  end

  def test_a_chain_renders_one_field_per_line
    query = Dagger::QueryBuilder.new.select("container").select("from", address: "alpine")
                                .select("withExec", args: %w[echo hi], useEntrypoint: nil).select("stdout")

    assert_equal <<~GRAPHQL.chomp, query.document
      query {
        container {
          from(address: "alpine") {
            withExec(args: ["echo", "hi"]) {
              stdout
            }
          }
        }
      }
    GRAPHQL
  end

  def test_a_node_query_loads_by_id_with_an_inline_fragment
    query = Dagger::QueryBuilder.new.select("container").node("id-1", "Container").select("stdout")

    assert_equal <<~GRAPHQL.chomp, query.document
      query {
        node(id: "id-1") {
          ... on Container {
            stdout
          }
        }
      }
    GRAPHQL
  end

  def test_an_empty_query_is_refused
    assert_raises(Dagger::InvalidQueryError) { Dagger::QueryBuilder.new.document }
  end

  def test_a_chain_is_immutable_and_snapshots_its_arguments
    args = ["echo"]
    base = Dagger::QueryBuilder.new.select("container")
    query = base.select("withExec", args:)
    args << "mutated"

    assert_equal 1, base.selections.size
    assert_equal ["echo"], query.selections.last.args[:args]
  end

  def test_execute_returns_the_selected_value_and_resolves_object_arguments
    engine = FakeEngine.new(
      [FakeEngine.data("directory" => { "id" => "dir-id" }),
       FakeEngine.data("container" => { "withDirectory" => { "id" => "ctr-id" } })]
    )
    session = Dagger::Session.new(Dagger::Connection.new(port: engine.port, token: "t"))
    root = Dagger::QueryBuilder.new(session:)
    directory = Thing.new(root.select("directory"))

    id = root.select("container").select("withDirectory", path: "/src", source: directory).select("id").execute

    assert_equal "ctr-id", id
    assert_includes engine.requests.last.query, 'withDirectory(path: "/src", source: "dir-id")'
  ensure
    session&.close
    engine&.close
  end

  def test_an_object_inside_an_input_object_is_sent_as_its_id
    with_session(FakeEngine.data("file" => { "id" => "file-id" }),
                 FakeEngine.data("host" => { "label" => "ok" })) do |root|
      label = Label.new(name: "n", value: Thing.new(root.select("file")))

      assert_equal "ok", root.select("host").select("label", input: [label]).execute
      assert_includes @engine.requests.last.query, 'label(input: [{name: "n", value: "file-id"}])'
    end
  end

  def test_a_nullable_object_is_nil_or_still_chainable
    with_session(FakeEngine.data("host" => { "stat" => nil }),
                 FakeEngine.data("host" => { "stat" => { "id" => "stat-id" } })) do |root|
      query = root.select("host").select("stat", path: "/x")

      assert_nil query.execute_optional(Thing)
      found = query.execute_optional(Thing)
      assert_instance_of Thing, found
      assert_equal query, found.query
    end
  end

  def test_a_null_for_a_required_field_is_refused_unless_allowed
    engine = FakeEngine.new([FakeEngine.data("a" => nil), FakeEngine.data("a" => nil)])
    session = Dagger::Session.new(Dagger::Connection.new(port: engine.port, token: "t"))
    query = Dagger::QueryBuilder.new(session:).select("a")

    assert_raises(Dagger::InvalidQueryError) { query.execute }
    assert_nil query.execute(allow_nil: true)
  ensure
    session&.close
    engine&.close
  end

  def test_a_list_of_objects_is_loaded_by_id
    with_session(FakeEngine.data("host" => { "things" => [{ "id" => "a" }, { "id" => "b" }] })) do |root|
      nodes = root.select("host").select("things").execute_object_list(Thing).map { it.query.selections.first }

      assert_equal(%w[a b], nodes.map { it.args[:id] })
      assert_equal(%w[Thing Thing], nodes.map(&:inline_type))
    end
  end

  def test_an_object_loaded_by_id_knows_it_without_a_query
    loaded = Thing.new(Dagger::QueryBuilder.new.node("known", "Thing"))

    assert_equal "known", loaded.id
    assert_nil Dagger::QueryBuilder.new.node("known", "Thing").select("parent").loaded_id
  end

  def test_an_id_result_is_reloaded_by_id
    with_session(FakeEngine.data("host" => { "sync" => "synced" })) do |root|
      synced = root.select("host").select("sync").execute_node(Thing)

      assert_equal "synced", synced.query.selections.first.args[:id]
      assert_equal "Thing", synced.query.selections.first.inline_type
    end
  end

  def test_an_id_is_fetched_once_per_object
    with_session(FakeEngine.data("directory" => { "id" => "dir-id" })) do |root|
      directory = Thing.new(root.select("directory"))

      2.times { assert_equal "dir-id", directory.id }
      assert_equal 1, @engine.requests.size
    end
  end

  # An object built through a field marked @reevaluate, and every object
  # chained on it, fetches its ID on every use.
  def test_a_reevaluated_object_and_its_chain_fetch_their_id_on_every_use
    fresh_id = ->(id) { FakeEngine.data("address" => { "container" => { "id" => id } }) }
    derived_id = ->(id) { FakeEngine.data("address" => { "container" => { "withEnvVariable" => { "id" => id } } }) }
    with_session(fresh_id["a"], fresh_id["b"], derived_id["c"], derived_id["d"]) do |root|
      fresh = Thing.new(root.select("address").select("container").reevaluate)
      derived = Thing.new(fresh.query.select("withEnvVariable", name: "A", value: "B"))

      assert_equal %w[a b], [fresh.id, fresh.id]
      assert_equal %w[c d], [derived.id, derived.id]
      assert_predicate derived.query, :reevaluated?
    end
  end

  def test_a_reevaluated_object_passed_as_an_argument_fetches_its_id_each_time
    fresh_id = ->(id) { FakeEngine.data("address" => { "container" => { "id" => id } }) }
    bound = ->(id) { FakeEngine.data("container" => { "withServiceBinding" => { "id" => id } }) }
    with_session(fresh_id["a"], bound["x"], fresh_id["b"], bound["y"]) do |root|
      fresh = Thing.new(root.select("address").select("container").reevaluate)
      2.times { root.select("container").select("withServiceBinding", alias: "a", service: fresh).select("id").execute }

      assert_includes @engine.requests[1].query, 'withServiceBinding(alias: "a", service: "a")'
      assert_includes @engine.requests[3].query, 'withServiceBinding(alias: "a", service: "b")'
    end
  end

  def test_a_reevaluation_condition_marks_only_the_calls_that_set_it
    root = Dagger::QueryBuilder.new

    refute_predicate root.select("file").reevaluate_when(nil, false), :reevaluated?
    assert_predicate root.select("file").reevaluate_when(nil, true), :reevaluated?
    assert_predicate root.select("file").reevaluate, :reevaluated?
  end

  def test_an_object_loaded_by_id_or_a_new_root_is_not_reevaluated
    fresh = Dagger::QueryBuilder.new.select("address").select("secret").reevaluate

    refute_predicate fresh.node("known", "Thing"), :reevaluated?
    refute_predicate fresh.root, :reevaluated?
    assert_predicate fresh.with_target(Dagger::Client::Target.new("t", "/", nil)), :reevaluated?
    assert_equal Dagger::QueryBuilder.new.select("address").select("secret"), fresh
  end

  private

  def with_session(*replies)
    engine = @engine = FakeEngine.new(replies)
    session = Dagger::Session.new(Dagger::Connection.new(port: engine.port, token: "t"))
    yield Dagger::QueryBuilder.new(session:)
  ensure
    session&.close
    engine&.close
  end
end
