module Greeter
  extend Dagger::Mod::Interface

  description "Anything that greets; the object of fixtures/clients/dep implements it."

  function "A greeting for someone."
  #: (name: String) -> String
  def greeting(name:) = raise(NotImplementedError)
end
