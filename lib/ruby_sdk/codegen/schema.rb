require "json"
require_relative "error"

class RubySdk
  module Codegen
    # The introspection JSON of a client-facing schema, with the directives the
    # engine attaches to types, fields, arguments and enum values.
    class Schema
      BUILTIN_SCALARS = %w[String Int Float Boolean ID].freeze

      attr_reader :version, :types

      def self.load(path) = new(JSON.parse(::File.read(path)))

      def initialize(document)
        schema = document["__schema"] || document.dig("data", "__schema") or raise Error, "not an introspection schema"
        @version = document["__schemaVersion"].to_s
        @types = schema.fetch("types").reject { it.fetch("name").start_with?("_") }.to_h { [it.fetch("name"), it] }
      end

      def [](name) = types.fetch(name) { raise Error, "the schema has no type #{name}" }

      def self.named(ref) = ref["ofType"] ? named(ref["ofType"]) : ref.fetch("name")

      def self.non_null?(ref) = ref.fetch("kind") == "NON_NULL"

      def self.directive(node, name)
        directive = (node["directives"] || []).find { it.fetch("name") == name } or return nil
        (directive["args"] || []).to_h { [it.fetch("name"), JSON.parse(it.fetch("value"))] }
      end

      def self.source_module(node) = directive(node, "sourceMap")&.fetch("module", nil)

      def self.expected_type(node) = directive(node, "expectedType")&.fetch("name", nil)

      def kind(name) = self[name].fetch("kind")

      def builtin_scalar?(name) = BUILTIN_SCALARS.include?(name)
    end
  end
end
