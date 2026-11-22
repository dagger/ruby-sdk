# Changelog

All notable changes to the Dagger SDK for Ruby. Releases are this
repository's tags.

## Unreleased

The first release. It requires Dagger v1.0.0-beta.26 or later.

### Added

- `sdk/entrypoint/dang.toml` in a module, written through `sdk-helpers`, with
  the Dagger version the module was generated for: v1.0.0-beta.27, which its
  `DAGGER_CLIENT_VERSION` and clients' API view also use. Generation manages
  that version and the language, and keeps other settings without comments or
  formatting.
- A workspace SDK: `dagger module install github.com/dagger/ruby-sdk`
  records it in `dagger.toml`, and `dagger generate` generates each Ruby
  scope, module or plain project.
- Modules on a generated Dang entrypoint (manifest v2), which run from their
  committed generated files and their current source. The entrypoint declares
  `sources`, so its `types` and `call` take no workspace.
- Module types as RBS `#:` annotations, read at generation, with refusals
  that name the file and line; the module's own RBS for Steep.
- Generated clients: the core API, each declared module, and
  `Dagger::Clients::Roots`, which gives a class one method per client.
- Plain Ruby programs that call the API and modules, under `dagger run` or
  with a session they start.
- `ruby-sdk:steep`, a check that runs generation's refusals and Steep on every
  Ruby module of the workspace, and `ruby-sdk mod --path <module> steep` for
  one.
- Collections: `collection`, and the `keys:`, `get:` and `delta:` markers.
- Gems outside a module's directory, named in its Gemfile, which the
  entrypoint's `sources` returns for the engine to load with the module.
- Objects built through a field marked `@reevaluate` fetch their ID on every
  use.
- Names from the engine: generated clients style each schema name with the
  engine's `formatIdentifiers` in snake case, at the target version.
- A module declares its functions, fields, arguments and members by their Ruby
  names (`load_json(base_url:)`), and the engine gives the API's
  (`loadJson(baseUrl:)`). A call through the module's own interface asks the
  engine for those names.
- The engine picks a module's main class among its classes, and names the
  class of a new module: `http-server` gives `HTTPServer`, `p11lib` gives
  `P11lib`. A class already named after the module by other rules keeps
  working: the engine takes `HttpServer` for `http-server` and `P11Lib` for
  `p11lib`.
- A failed function fails its call with its own error: in the engine's
  function error file (`DAGGER_FUNCTION_ERROR_PATH`) where the engine gives
  one, with the values of the API error it was raised from, and a short trace
  of the module's own frames in its logs; on an older engine, with its message.
  The entrypoint marks its function's exec with `DAGGER_MODULE_CALL_DIGEST`,
  and declares the gems' install as its `prebuild`.
