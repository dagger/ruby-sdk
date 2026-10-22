require "dagger"
require "dagger/clients/dep"

puts Dagger::Clients::Dep.dep.greeting(name: "plain")
