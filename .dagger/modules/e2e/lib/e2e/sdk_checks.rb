class E2E
  TESTS = 'Dir["test/**/*_test.rb"].each { require File.expand_path(it) }'.freeze
  CODEGEN = <<~RUBY.freeze
    require "codegen/codegen_helper"
    RubySdk::Codegen::Package.write(CodegenHelper.client_files, "tmp/codegen/greeter")
    RubySdk::Codegen::Package.write(CodegenHelper.roots_files, "tmp/codegen/roots")
  RUBY

  function "Minitest passes on the library, the SDK module and the generator.", check: true
  #: (ws: Core::Workspace) -> void
  def sdk_test_check(ws:) = unit(ws, "ruby", "-Itest", "-e", TESTS)

  function "RuboCop passes on the repository.", check: true
  #: (ws: Core::Workspace) -> void
  def sdk_lint_check(ws:) = unit(ws, "rubocop")

  function "Steep passes on the library, the SDK module and the generated core.", check: true
  #: (ws: Core::Workspace) -> void
  def sdk_types_check(ws:) = unit(ws, "steep", "check")

  private

  # A stale tmp/codegen of the workspace would mix with the clients
  # generated here, which Steep checks.
  def unit(ws, *command)
    development_image(ws).with_directory(path: "/src", source: tree(ws).without_directory(path: "tmp"))
                         .with_workdir(path: "/src")
                         .with_env_variable(name: "BUNDLE_GEMFILE", value: "/tools/Gemfile")
                         .with_exec(args: %w[ruby lib/ruby_sdk/codegen/cli.rb core test/fixtures/core-schema.json
                                             tmp/codegen/core])
                         .with_exec(args: ["ruby", "-Itest", "-e", CODEGEN])
                         .with_exec(args: ["bundle", "exec", *command])
                         .sync
    nil
  end
end
