require "dagger"
require "dagger/clients/roots"
require_relative "collections/item"
require_relative "collections/items"
require_relative "collections/suite"
require_relative "collections/suites"

# Collections for the collection checks: Items marks its members, Suites
# names them as the engine does.
class Collections
  extend Dagger::Mod::Object
  include Dagger::Clients::Roots

  function "Three items: b, a and c."
  #: () -> Items
  def items = Items.new(names: %w[b a c], prefix: "item:")

  function "Two suites."
  #: () -> Suites
  def suites = Suites.new(keys: %w[unit lint])

  function "The artifacts of a workspace."
  #: (ws: Dagger::Clients::Core::Workspace) -> Dagger::Clients::Core::Artifacts
  def artifacts(ws:) = ws.artifacts

  function "The dimensions of a workspace's artifacts, read in the module."
  #: (ws: Dagger::Clients::Core::Workspace) -> Array[String]
  def dimensions(ws:) = ws.artifacts.dimensions
end
