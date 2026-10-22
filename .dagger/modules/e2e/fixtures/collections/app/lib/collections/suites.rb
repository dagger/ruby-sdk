class Suites
  extend Dagger::Mod::Object

  collection

  field :keys #: Array[String]
  field :delta #: Dagger::Clients::Core::CollectionDelta?

  function
  #: (key: String) -> Suite
  def get(key:) = Suite.new(name: key)

  function "Passes when the selection removed no suite.", check: true
  #: () -> void
  def complete
    removed = delta&.removed_keys || []
    raise "the selection removed #{removed.join(", ")}" unless removed.empty?
  end
end
