require "dagger"
require "dagger/clients/roots"

class IncludeCaller
  extend Dagger::Mod::Object
  include Dagger::Clients::Roots

  description "Reaches the include app through its generated client."

  function "The app's word."
  #: () -> String
  def word = include_app.word
end
