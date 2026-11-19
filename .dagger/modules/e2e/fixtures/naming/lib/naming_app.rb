require "dagger"
require "dagger/clients/dep"
require_relative "naming_app/arch"
require_relative "naming_app/loader"

class NamingApp
  extend Dagger::Mod::Object

  description "Ruby names that the engine names, called by engineNamingCheck."

  function "Where JSON loads from."
  #: (base_url: String) -> String
  def load_json(base_url:) = "#{base_url}/app.json"

  function "An enum member with a digit."
  #: () -> Arch
  def arch = Arch::ARM64

  function "The dep client's object, as an interface."
  #: () -> Loader
  def loader = Dagger::Clients::Dep.dep

  function "A call through the module's own interface."
  #: (loader: Loader, base_url: String) -> String
  def load_through(loader:, base_url:) = loader.load_json(base_url:)
end
