require "dagger"
require "dagger/clients/roots"

# Top-level code gets the client methods on the main object alone; this is
# the form under test, so the cop against it is off here.
extend Dagger::Clients::Roots # rubocop:disable Style/MixinUsage

class Greeter
  include Dagger::Clients::Roots

  def greet = dep.greeting(name: "from a class")
end

puts dep.greeting(name: "from the top level")
puts Greeter.new.greet
