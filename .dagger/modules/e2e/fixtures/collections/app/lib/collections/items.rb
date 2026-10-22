class Items
  extend Dagger::Mod::Object

  collection

  field :names, keys: true #: Array[String]
  field :selection, delta: true #: Dagger::Clients::Core::CollectionDelta?
  field :prefix #: String

  function get: true
  #: (name: String) -> Item
  def lookup(name:) = Item.new(name: "#{prefix}#{name}")

  function "The keys of this selection."
  #: () -> Array[String]
  def selected = names

  function "The keys this selection removed from its base."
  #: () -> Array[String]
  def removed = selection&.removed_keys || []

  function "The keys this selection added to its base."
  #: () -> Array[String]
  def added = selection&.added_keys || []

  function "A copy with other keys, which keeps its base."
  #: (names: Array[String]) -> Items
  def change(names:)
    dup.tap do |copy|
      copy.instance_variable_set(:@names, names)
      copy.instance_variable_set(:@selection, nil)
    end
  end
end
