require_relative "lib/shared/version"

Gem::Specification.new do |spec|
  spec.name = "shared"
  spec.version = Shared::VERSION
  spec.summary = "A gem outside the module that uses it."
  spec.authors = ["Dagger"]
  spec.required_ruby_version = ">= 3.4"
  spec.files = Dir["lib/**/*"]
end
