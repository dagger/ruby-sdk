require "dagger"
require "securerandom"
require "shared"

class IncludeApp
  extend Dagger::Mod::Object

  description "A module that uses a gem outside its directory, beside it."

  function "The shared gem's word, from a file of the gem."
  #: () -> String
  def word = Shared.word

  function "A value of its own each time the call runs."
  #: () -> String
  def nonce = SecureRandom.hex(8)
end
