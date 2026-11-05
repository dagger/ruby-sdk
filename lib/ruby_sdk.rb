require "dagger"
require "dagger/clients/core"
require_relative "ruby_sdk/scope"
require_relative "ruby_sdk/steep"

# The Ruby half of the SDK module. ruby-sdk.dang declares the functions and
# their types, and runs these through lib/ruby_sdk/call.rb.
class RubySdk
  TEMPLATES = %w[default empty].freeze

  attr_reader :template, :ruby_version

  def initialize(template:, ruby_version:, target_version:)
    @template = template
    @ruby_version = ruby_version
    @target_version = target_version
  end

  def find_client_root(ws:) = Scope.find_root(ws)

  def generate_scope(ws:, is_module:, name:, clients:)
    raise Error, "no template #{template.inspect}: choose #{TEMPLATES.join(" or ")}" unless TEMPLATES.include?(template)

    Scope.new(ws:, is_module:, name:, clients:, sdk: source, image:, target_version: @target_version, template:,
              ruby_version:).generated
  end

  def steep(ws:, path: nil) = Steep.new(ws:, image:, target_version: @target_version).check(path)

  private

  def source = Dagger::Mod.module_source

  def image
    source.file(path: "images/ruby/Dockerfile").contents[/^FROM (\S+)/, 1] or
      raise Error, "images/ruby/Dockerfile of the SDK module has no FROM line"
  end
end
