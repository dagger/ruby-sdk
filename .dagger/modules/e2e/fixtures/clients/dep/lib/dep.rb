require "dagger"

class Dep
  extend Dagger::Mod::Object

  description "The target of the scope generation checks."

  function "Greet someone."
  #: (?name: String) -> String
  def greeting(name: "world") = "hello, #{name}"

  function "Where JSON loads from: the naming fixture's interface."
  #: (base_url: String) -> String
  def load_json(base_url:) = "#{base_url}/dep.json"
end
