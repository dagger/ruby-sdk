require "dagger"

class Dep
  extend Dagger::Mod::Object

  description "The target of the scope generation checks."

  function "Greet someone."
  #: (?name: String) -> String
  def greeting(name: "world") = "hello, #{name}"
end
