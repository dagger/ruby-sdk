require "dagger"
require "dagger/clients/core"
require "securerandom"
require_relative "app/greeting"

class App
  extend Dagger::Mod::Object

  description "The main module fixture."

  field :greeting, default: "hello" #: String

  function "Greet someone."
  #: (?name: String) -> String
  def greet(name: "world") = Greeting.new(greeting).to(name)

  function "The engine's version."
  #: () -> String
  def version = Dagger::Clients::Core.core.version

  function "A value of its own each time the call runs."
  #: () -> String
  def nonce = SecureRandom.hex(8)
end
