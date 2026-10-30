require_relative "../test_helper"
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "dagger/mod"
require "ruby_sdk/signatures"

module ModHelper
  TARGET_VERSION = File.read(File.expand_path("../../ruby-sdk.dang", __dir__))[/let targetVersion: String! = "([^"]+)"/,
                                                                               1]

  # Declares classes the way a module file does, under a namespace of their
  # own, with a fresh registry each time.
  module Fixtures; end

  # What generated core gives a module, without generating it.
  module Core
    class Container < Dagger::Type; end
    class Directory < Dagger::Type; end
    class Workspace < Dagger::Type; end
    class CollectionDelta < Dagger::Type; end
    class JSON < Dagger::Scalar; end
    class NetworkProtocol < Dagger::Enum; end

    # A client's type, whose GraphQL name is not its constant's.
    class Thing < Dagger::Type
      def self.graphql_name = "ClientThing"
    end
  end

  def setup
    Dagger::Mod.reset_registry!
    Fixtures.constants.each { Fixtures.send(:remove_const, it) }
    @sources = {}
  end

  # Loads the source as its file would, under Fixtures, and reads its
  # annotations from the same text, as generation does. The wrapper keeps
  # line numbers; each source is a file of its own, lib/main.rb first.
  def declare(source)
    path = @sources.empty? ? "lib/main.rb" : "lib/main#{@sources.size}.rb"
    @sources[path] = "module ModHelper; module Fixtures; #{source}\nend; end\n"
    TOPLEVEL_BINDING.eval(@sources[path], path)
  end

  def signatures = Dagger::Mod::Signatures.new(JSON.parse(JSON.generate(RubySdk::Signatures.parse(@sources))))

  def annotate = Dagger::Mod.registry.annotate(signatures)

  def describe(main = "Main")
    annotate
    Dagger::Mod.registry.describe(main)
  end

  def object(description, name) = description.objects.find { it.name == name }

  def function(description, object_name, name) = object(description, object_name).functions.find { it.name == name }
end
