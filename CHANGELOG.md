# Changelog

All notable changes to the Dagger SDK for Ruby. Releases are this
repository's tags.

## Unreleased

The first release. It requires Dagger v1.0.0-beta.19 or later.

### Added

- `sdk/entrypoint/dang.toml` in a module, written through `sdk-helpers`, with
  the Dagger version the module was generated for: v1.0.0-beta.21, which its
  clients' API view also uses. Generation manages that version and the
  language, and keeps other settings without comments or formatting.
- A workspace SDK: `dagger module install github.com/dagger/ruby-sdk`
  records it in `dagger.toml`, and `dagger generate` generates each Ruby
  scope, module or plain project.
- Modules on a generated Dang entrypoint (manifest v2), which run from their
  committed generated files and their current source.
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
