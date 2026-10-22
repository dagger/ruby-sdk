require "dagger"

class ConfigApp
  extend Dagger::Mod::Object

  function "The Ruby that runs the module."
  #: () -> String
  def ruby_version = RUBY_VERSION
end
