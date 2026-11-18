module Loader
  extend Dagger::Mod::Interface

  description "Loads JSON; the object of fixtures/clients/dep implements it."

  function "Where JSON loads from."
  #: (base_url: String) -> String
  def load_json(base_url:) = raise(NotImplementedError)
end
