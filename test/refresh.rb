# Records core's client-facing schema through the stand-in, then rewrites the
# goldens from it. The e2e module's goldens generator runs it in the
# development image.
require "json"
$LOAD_PATH.unshift File.expand_path("../sdk/lib", __dir__), File.expand_path("../lib", __dir__)
require "dagger"
require "ruby_sdk/codegen/stand_in"

root = Dagger::QueryBuilder.new.select("directory")
directory = RubySdk::Codegen::StandIn::FILES.reduce(root) do |query, (path, contents)|
  query.select("withNewFile", path:, contents:)
end
schema = directory.select("asModuleSource").select("clientSchemaIntrospectionJSON").select("contents").execute
File.write(File.expand_path("fixtures/core-schema.json", __dir__),
           "#{JSON.pretty_generate(JSON.parse(schema))}\n")

require_relative "codegen/codegen_helper"
require_relative "mod/mod_helper"
require "dagger/mod"

golden = File.expand_path("golden", __dir__)
write = lambda do |path, contents|
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, contents)
end
{ "codegen" => [CodegenHelper::GOLDEN_FILES, CodegenHelper.core_files],
  "codegen-roots" => [CodegenHelper::ROOTS_GOLDEN_FILES, CodegenHelper.roots_files],
  "codegen-client" => [CodegenHelper::CLIENT_GOLDEN_FILES, CodegenHelper.client_files] }.each do |dir, (paths, files)|
  paths.each { write.call(File.join(golden, dir, it), files.fetch(it)) }
end

helper = Object.new.extend(ModHelper)
helper.setup
helper.declare(File.read(File.expand_path("fixtures/entrypoint/lib/main.rb", __dir__)))
entrypoint = Dagger::Mod::Entrypoint
write.call(File.join(golden, "mod/types.dang"), entrypoint.render_types(helper.describe("Main")))
write.call(File.join(golden, "mod/module.rbs"), entrypoint.render_rbs(Dagger::Mod.registry))
write.call(File.join(golden, "mod/main.dang"), entrypoint.render_main("main"))
write.call(File.join(golden, "mod/main-sources.dang"),
           entrypoint.render_main("main", outside: ["../shared"], outside_files: ["../Gemfile.common"]))
build = Dagger::Mod::Build.new(image: "ruby:4.0@sha256:#{"0" * 64}", module_name: "my-module",
                               gemspecs: %w[sdk/dagger-sdk.gemspec clients/core/dagger-clients-core.gemspec])
write.call(File.join(golden, "mod/build.dang"), build.to_dang)
