# Working on the Ruby SDK

This file is for a maintainer or a coding agent changing this repository. The
README says how to use the SDK; `hack/designs/ruby-sdk-design.md` says how it
is built and why.

## What this repository is

A Dagger workspace SDK for Ruby. The repository's root is the SDK module:
`dagger module install github.com/dagger/ruby-sdk` records it, and
`dagger generate` asks it to generate each Ruby scope of a workspace, a module
or a plain project.

| Path | What it holds |
| --- | --- |
| `ruby-sdk.dang`, `ruby-half.dang`, `mod.dang` | The SDK module: a thin Dang wrapper (`[runtime] source = "dang"` in `dagger-module.toml`). `ruby-sdk.dang` declares the API; `ruby-half.dang` runs `lib/ruby_sdk.rb` in an exec on the pinned image |
| `lib/ruby_sdk/` | Generation (`scope.rb`), the Steep check (`steep.rb`), annotation parsing (`signatures.rb`), gems outside a module (`resources.rb`), the client generator (`codegen/`) |
| `sdk/` | The `dagger-sdk` gem that every scope vendors: sessions, the query builder, and `Dagger::Mod`, the module runtime that also renders `main.dang`, `types.dang` and `build.dang` |
| `clients/` | The SDK module's own generated core and roots clients, from the plain scope `.` |
| `templates/` | What `dagger module init ruby` writes: `default` and `empty` |
| `images/ruby/Dockerfile` | The pinned Ruby image that modules build on |
| `sig/` | RBS for `lib/` |
| `test/` | Minitest: `test/fixtures/core-schema.json` is the schema the generator's tests read, `test/golden/` the expected output |
| `.dagger/modules/e2e/` | The end-to-end harness, itself a generated Ruby module; its fixture scopes are sources only (`fixtures/scopes.toml`) |
| `hack/` | The scripts below, the development image (`dev.Dockerfile`, `tools/`), `unit.rb` and the design note |

The SDK module's `include` (`dagger-module.toml`) lists what its exec reads:
the Dang files, the Gemfiles, `lib/`, `sdk/`, `clients/`, `templates/` and
`images/`. `test/`, `hack/`, `sig/` and `.dagger/` are not part of it.
`ruby-sdk.dang` declares the API, and a unit test keeps `RubySdk`'s public
methods equal to it. The Ruby half is the plain scope `.` of this
repository's `dagger.toml`: an edit to `lib/` runs at once; after an edit to
its `Gemfile`, each call relocks in its container until `bundle lock`, run in
the pinned image, relocks the scope.

## Checks

Every check runs on a dedicated engine container, `dagger-engine.ruby-sdk`.
The host needs Docker and the `dagger` CLI; it needs no Ruby.

```sh
hack/engine.sh start          # the released engine of the CLI's own version
hack/e2e.sh                   # everything; must pass before a change lands
hack/e2e.sh sdk-test-check    # named checks only (clientCacheCheck still runs)
hack/engine.sh remove         # the container and its volume
```

`hack/e2e.sh` copies the tree to a scratch directory (`E2E_SCRATCH`, by
default `~/.cache/ruby-sdk/e2e`), checks that generation leaves the committed
files unchanged, registers and generates the fixture scopes one per pass, then
runs `dagger check -m .dagger/modules/e2e` and `clientCacheCheck` alone. The
harness's checks include:

| Check | What it runs |
| --- | --- |
| `sdk-test-check` | Minitest over `test/` (`ruby hack/unit.rb test` in the development image) |
| `sdk-lint-check` | RuboCop |
| `sdk-types-check` | Steep over `lib/`, `sdk/` and a generated core |
| `modules-steep-check` | `ruby-sdk:steep` over the fixture modules |
| `plain-program-check` | a plain Ruby program with a client, under `dagger run` and with a session it provisions |

`. hack/engine.env`, from anywhere in the repository, points a shell at the
same engine. Unit tests, RuboCop and Steep then run straight from the tree, without
the scratch copy:

```sh
. hack/engine.env && dagger check -m .dagger/modules/e2e sdk-test-check sdk-lint-check sdk-types-check
```

The README's quickstart is the user path: run it as written in an empty git
directory, with the SDK installed by path:

```sh
. hack/engine.env
ws=$(mktemp -d) && git -C "$ws" init -q
rsync -a --relative $(ruby_sdk_module_files) "$ws/ruby-sdk/"
cd "$ws" && dagger module install ./ruby-sdk
# then each command of the README's Quickstart; a second dagger generate changes nothing
```

## Engines

The SDK requires Dagger v1.0.0-beta.19 or later. That is documentation only:
nothing checks the version.

`hack/engine.env` points `DAGGER_ENGINE` at the dedicated container, hides any
Dagger Cloud login (`XDG_CONFIG_HOME`), and leaves other engines alone
(`DAGGER_LEAVE_OLD_ENGINE`). `hack/engine.sh start` runs
`registry.dagger.io/engine:<version>` for the CLI's own version, so CLI and
engine always match, on an empty volume whenever that version changes.

- A custom engine: start it, then set `DAGGER_ENGINE` to it and `RUBY_SDK_CLI`
  to its CLI, and run `hack/e2e.sh`.
- Slow Docker Hub pulls: `RUBY_SDK_ENGINE_REGISTRY_MIRROR=mirror.gcr.io
  hack/engine.sh start` gives the engine a mirror for `docker.io`. One slow
  connection stalls a whole pull; restarting the engine resumes it.
- The first run pulls the Ruby image and builds the development image. Warm
  the engine first, after `. hack/engine.env`, from a directory that is not a
  workspace:
  `img=$(sed -n 's/^FROM //p' images/ruby/Dockerfile); (cd /tmp && dagger -c "container | from $img | sync")`.
- No `dagger.lock` is committed, and nothing here writes one. An ad-hoc
  `container | from` at a workspace's root does: delete it.
- Bundler's cache is the `ruby-sdk-bundle` cache volume, with a directory per
  module. Bundler names its temporary files by process ID, which repeats
  across containers: builds that share one directory fail at once.
- The CLI asks before it applies changes, refuses to ask without a terminal,
  and asks a coding agent for `-y` or `--no-apply` instead (v1.0.0-beta.19):
  pass `-y` to `dagger generate`, `dagger module init` and
  `dagger module client add` in scripts.

## Generated files

Generated files are committed and never edited by hand; every generated
member directory carries a `.dagger-generated` marker. After a change to the
generator, `sdk/`, `templates/` or the engine's schema:

```sh
hack/refresh.sh
```

It rewrites the schema fixture and the goldens in the development image, runs
`dagger generate -y`, then generates the root's plain scope, which
`dagger generate` skips:
`dagger -c 'ruby-sdk | generate-scope false "" "" | export'`. Commit what it
writes. Each client records the core it was generated against
(`CORE_DIGEST`), so a stale client fails to load. `hack/e2e.sh` fails on any
file that generation would change, the root's core included. An edit to a
harness file shifts the line numbers in its `signatures.json`, which
`hack/refresh.sh` rewrites.

## Rules

- Generation happens at `dagger generate` only. A module runs from its
  committed generated files, on manifest v2 with a generated Dang entrypoint,
  and on its current source; a call runs no code generation.
- The SDK module stays a thin Dang wrapper at the root; the Ruby half runs in
  an exec and reads its own files from `currentModule.source`.
- Types come from `#:` RBS annotations, parsed at generation into
  `sdk/entrypoint/signatures.json`; the DSL carries what a type cannot say.
- No engine version checks in code. A feature that needs a newer engine is
  detected by its schema, as `CurrentModule.contextDirectory` is.
- A passing `dagger check ruby-sdk:steep` means `dagger generate` accepts the
  module: the Steep check runs generation's own refusals, the same methods of
  `RubySdk::Scope`.
- The entrypoint contract: `types` returns the literal typedefs; `call` runs
  `dagger-mod call` with the request on stdin and declares a nullable
  `callDigest`, which keys its exec. A module with gems outside its directory
  declares `sources`, and its `types` and `call` take no workspace; every other
  module keeps `types(workspace:)` and `call(workspace:, …)`.
- Code style: RuboCop's configuration, lines up to 120 characters, comments
  that say why, not what. In Steep, a literal symbol widens to `Symbol`
  (annotate `Symbol?`), `grep` does not narrow (use a local and `is_a?`), and
  an empty hash needs an annotation (`{} #: Hash[…]`).

## Known engine limitations

The README lists them. A function that returns a nested list of scalars comes
back as rows of IDs; `typesRoundTripCheck` checks nested lists as arguments
only.

## Commits

One logical change per commit, each passing `hack/e2e.sh`. Subjects follow
the repository's history: a type and an optional scope, then an imperative,
lowercase summary (`feat(sdk): …`, `fix(mod): …`, `test: …`, `docs: …`,
`chore: …`, `ci: …`). The body says why in one to three lines. Commits are
signed off (`git commit -s`).
