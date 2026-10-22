require "dagger"
require "dagger/clients/roots"

# Reaches the collections module through its generated client.
class CollectionsCaller
  extend Dagger::Mod::Object
  include Dagger::Clients::Roots

  function "The keys of a subset."
  #: () -> Array[String]
  def subset_keys = collections.items.subset(keys: %w[c b]).keys

  function "The keys a subset removed, through its batch."
  #: () -> Array[String]
  def removed = collections.items.subset(keys: %w[a]).batch.removed

  function "An item's name, through get."
  #: () -> String
  def item = collections.items.get(key: "a").name

  function "Every item's name, through list."
  #: () -> Array[String]
  def names = collections.items.list.map(&:name)
end
