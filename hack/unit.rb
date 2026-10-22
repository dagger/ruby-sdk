# Runs the unit tests, RuboCop and Steep, or the steps named:
# ruby hack/unit.rb [test] [lint] [types]
require "fileutils"

ENV["BUNDLE_GEMFILE"] = "/tools/Gemfile"
steps = ARGV.empty? ? %w[test lint types] : ARGV

def run(*command)
  system(*command) || abort("hack/unit.rb: #{command.first(3).join(" ")} failed")
end

FileUtils.rm_rf("tmp/codegen")
run "ruby", "lib/ruby_sdk/codegen/cli.rb", "core", "test/fixtures/core-schema.json", "tmp/codegen/core"
run "ruby", "-Itest", "-e", 'require "codegen/codegen_helper"
  RubySdk::Codegen::Package.write(CodegenHelper.client_files, "tmp/codegen/greeter")
  RubySdk::Codegen::Package.write(CodegenHelper.roots_files, "tmp/codegen/roots")'
if steps.include?("test")
  run "bundle", "exec", "ruby", "-Itest", "-e", "ARGV.each { require File.expand_path(it) }",
      *Dir["test/**/*_test.rb"]
end
run "bundle", "exec", "rubocop" if steps.include?("lint")
run "bundle", "exec", "steep", "check" if steps.include?("types")
