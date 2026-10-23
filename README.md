# Dagger SDK for Ruby

> [!WARNING]
> This SDK is experimental: expect breaking changes. Generated files, the DSL
> and the API may change without notice. It is not recommended for production
> yet.

Write [Dagger](https://dagger.io) modules in Ruby, and call the Dagger API and
other modules from Ruby: from a module, or from a plain Ruby program.

- A module declares its API with RBS type annotations, which Steep checks too.
- Each scope gets generated clients: the core API, and each module it uses.
- Generation runs at `dagger generate`. A module runs from its committed
  generated files, on a generated Dang entrypoint, and on its current source:
  an edited function body runs without generating again.
- Checks, collections, core artifacts and gems outside a module's directory
  are supported.

## Requirements

- Dagger v1.0.0-beta.19 or later, its CLI and engine. The SDK checks no
  version: on an older engine, what it lacks fails where it is used.
- No Ruby on the host for modules: they build in containers, on the SDK's
  pinned Ruby 4.0 image, or on `ruby:<version>` with a `.ruby-version`. A
  plain Ruby program needs Ruby 3.4 or later and Bundler.

## Install

```sh
dagger module install github.com/dagger/ruby-sdk
```

This records the SDK module and `[sdks.ruby]` in the workspace's
`dagger.toml`. The repository's root is the SDK module. A release installs by
its tag: `dagger module install github.com/dagger/ruby-sdk@<tag>`.

## Quickstart

Create a module, then give it a function and a check:

```sh
dagger module init ruby --name hello
```

```ruby
# .dagger/modules/hello/lib/hello.rb
require "dagger"
require "dagger/clients/roots"

class Hello
  extend Dagger::Mod::Object
  include Dagger::Clients::Roots

  function "Greet someone."
  #: (?name: String) -> String
  def greet(name: "world") = "hello, #{name}"

  function "The greeting is polite.", check: true
  #: () -> void
  def polite
    raise "not polite: #{greet}" unless greet.start_with?("hello")
  end
end
```

```sh
dagger generate                          # read the annotations, write the entrypoint
dagger call -m hello greet --name Ruby   # hello, Ruby
dagger check                             # hello's check, and Steep over every Ruby module
```

Call it from another module through a generated client:

```sh
dagger module init ruby --name app
(cd .dagger/modules/app && dagger module client add ../hello)
```

```ruby
# .dagger/modules/app/lib/app.rb, in class App, which includes the client roots
function "Welcome through hello."
#: () -> String
def welcome = hello.greet(name: "app")
```

```sh
dagger generate
dagger call -m app welcome               # hello, app
```

The rest of this README covers each part: the scope's tree, declaring a
module and its types, collections, type checking, clients and plain programs,
gems outside a module, errors, and how to contribute.

## Create a module

```sh
dagger module init ruby --name hello
dagger module init ruby --name hello --template empty --ruby-version 3.4
```

`--template` is `default` (a `container` function over the workspace) or
`empty`. `--ruby-version` writes `.ruby-version`, and the module then builds
and locks on the `ruby:<version>` image instead of the SDK's pinned Ruby 4.0
image. Both are scope settings: `dagger.toml` keeps them, and every
`dagger generate` passes them again.

The module's name gives its main class by the engine's rule (`hello` gives
`Hello`, `my-module` gives `MyModule`, `e2e` gives `E2E`), and its file is
`lib/<snake_case name>.rb`.

## The tree of a scope

```
<scope>/
  Gemfile              yours; evaluates dagger.gemfile
  Gemfile.lock         a module always has one, written by its image's Bundler
  dagger.gemfile       generated: one path gem per member
  .ruby-version        yours, optional
  Steepfile            yours, from the template
  lib/                 yours
  sdk/                 generated: the dagger-sdk gem, and a module's entrypoint,
                       signatures read from its annotations and module.rbs
  clients/core/        generated: the core API
  clients/roots/       generated: core and each client as private methods
  clients/<name>/      generated: one per declared client
  dagger-module.toml   generated, modules only: name and [entrypoint]
```

Each generated member holds a `.dagger-generated` marker naming its kind. A
directory where a member goes without that marker is yours: generation refuses
to write over it, and never deletes anything under `clients/` but a member it
wrote. The `Gemfile` gets one line, `eval_gemfile "dagger.gemfile"`, when it
lacks it, and nothing else.

A module's manifest is exactly:

```toml
name = "hello"

[entrypoint]
kind = "dang"
source = "./sdk/entrypoint"
```

Generation refuses a manifest with `[runtime]`, `[[dependencies]]`,
`engineVersion`, `include`, `exclude`, a `source` other than `.`, or another
entrypoint, naming what it found, and refuses a `dagger.json`.

## Declaring a module

Types are RBS, Ruby's type signatures, in `#:` comments: at the end of a
field's line, and right above a method. `dagger generate` reads them, and
Steep checks the code against them (see Type checking). What a type cannot
say is declared right before the `def`:

```ruby
# lib/hello.rb
require "dagger"
require "dagger/clients/roots"

class Mood < Dagger::Mod::Enum
  member :HAPPY, "happy"
  member :GRUMPY, "grumpy", doc: "Before coffee."
end

class Hello
  extend Dagger::Mod::Object
  include Dagger::Clients::Roots

  description "Greetings."

  field :greeting, default: "hello" #: String

  function "Greet someone."
  arg :name, doc: "Who to greet."
  #: (?name: String, ?mood: Mood) -> String
  def greet(name: "world", mood: Mood::HAPPY) = "#{greeting}, #{name} (#{mood.value})"

  function "Build the module's own source.", check: true
  #: () -> void
  def build
    core.container.from(address: "ruby:4.0")
        .with_directory(path: "/src", source: Dagger::Mod.module_source)
        .with_exec(args: ["rake"]).sync
    nil
  end
end
```

- `extend Dagger::Mod::Object` registers a class, `extend Dagger::Mod::Interface`
  a module whose functions are declarations only (`def speak = raise(NotImplementedError)`),
  and `class X < Dagger::Mod::Enum` an enum whose members are upper snake case.
- `include Dagger::Clients::Roots`, which both templates put in the main class,
  gives the class one private method per client of the scope: `core`, and for
  a client `lib` the method `lib(...)`, with the arguments and types of
  `Dagger::Clients::Lib.lib(...)`, which keeps working. A method's name is the
  engine's constructor field for the module in snake case: `p11lib` gives
  `p11_lib`, `MyModule` `my_module`, `s3-bucket` `s3_bucket`. `dagger generate`
  rewrites `clients/roots/` with the scope's clients, so `module client add`
  adds a method and `module client remove` drops it. The methods are instance
  methods: `def self.create`, the class body and classes nested in the class
  use the long form, `Dagger::Clients::Core.core`. Types are constants:
  `Dagger::Clients::Core::Directory`. Generation refuses, naming both, a
  field, function, constructor argument or method of the class with the name
  of a client method, and a client whose method would be a Ruby keyword or a
  method every object has (`tap`, `format`, `display`, ...).
- `field :name, default:, ignore:, private:, doc:, deprecated: #: Type`
  declares state; its type is the `#:` comment that ends its line. On the main
  class without `constructor`, the fields are the constructor's arguments.
- `function "doc", name:, check:, generator:, start:, agent:, deprecated:`
  declares the next instance method. `constructor` declares `def self.create`
  on the main class, annotated like a function, returning the class.
- A function's annotation is its method type, keywords only, one signature:
  `#: (name: String, ?mood: Mood) -> String`. It comes after `function` and
  `arg`, right above the `def`. A `?` keyword has its default in the `def`.
  That default is the API's when it is a literal, or a constant that holds one
  or names an enum member; any other default is Ruby's alone, and the argument
  is then optional to callers. RBS's other form, one `# @rbs name: Type` line
  per keyword and `# @rbs return: Type`, works too, without text after `--`.
- `arg :name, doc:, name:, default_address:, ignore:, deprecated:` gives an
  argument what its type cannot: a description, an API name, engine options.
- Names in an annotation resolve as constants in the class body do.
- `Dagger::Mod.module_source` is the module's own directory, during a call.
  No argument is filled with a directory of the context: the engine resolves
  one against the caller's workspace, which holds the module only when the
  module sits in it.
- A method name ending in `?` or `!` needs `name:`. `snake_case` names become
  `camelCase` in the API.
- Top-level code of a module file must not call the API: generation loads the
  files without a session.

Generation refuses, naming the file and line: a function without an
annotation, an annotation that does not parse or that sits above `function`
and so belongs to no `def`, one whose keywords disagree with the `def`, a
field without a type, and a type the API cannot carry.

| Annotation | API type |
| --- | --- |
| `String`, `Integer`, `Float` | `String!`, `Int!`, `Float!` |
| `bool` | `Boolean!` |
| `void` or `nil`, as a result | `Void` |
| `T?`, or `T \| nil` | `T`, nullable |
| `Array[T]` | `[T!]!` |
| a class with `extend Dagger::Mod::Object`; `self` or `instance` for the class itself | the module's object |
| a module with `extend Dagger::Mod::Interface` | the module's interface |
| a `Dagger::Mod::Enum` subclass | the module's enum |
| `Dagger::Clients::Core::Directory`, any core or client class | that object |
| `Dagger::Clients::Core::JSON`, any core scalar | that scalar |
| `untyped`, another union, `Hash[K, V]`, a tuple, a record, a type alias, `Symbol`, `Object` | refused |

An interface argument arrives as the implementing object; its calls are
served through the module's clients, so the implementation must come from a
module the scope declares as a client.

### Collections

A collection is an object of many items, selected by key. The engine gives it
`keys`, `get`, `list`, `subset` and `batch`; a check of its item type runs
once per item, and its other functions run on a selection, under `batch`.

```ruby
class Items
  extend Dagger::Mod::Object
  collection

  field :keys #: Array[String]
  field :delta #: Dagger::Clients::Core::CollectionDelta?

  function
  #: (key: String) -> Item
  def get(key:) = Item.new(name: key)

  function "The keys this selection removed."
  #: () -> Array[String]
  def removed = delta&.removed_keys || []
end
```

- `collection` marks the class. Its members go by the engine's names: the
  field `keys`, a list of strings, numbers, booleans, scalars or enum members,
  none of them nil; the function `get`, which takes one required argument of
  the key type and returns an object; and, if declared, the field `delta`, a
  `Dagger::Clients::Core::CollectionDelta`, which the engine fills with the
  keys a selection added and removed.
- A member of another name is marked: `field :names, keys: true`,
  `function get: true` above `def lookup(name:)`, `field :changes, delta: true`.
- A copy of the receiver, `dup`, keeps the collection it was selected from, so
  its delta is computed against that; an object made with `new` has none.
- Generation refuses, naming the file and line, a collection without keys or
  get, a member of the wrong type, two members marked for one role, and a
  marker outside a collection.
- `Dagger::Clients::Core::Artifacts` and the other artifact types are core
  types: a function returns them, or reads a workspace's artifacts, with
  nothing more to declare.

## Type checking

A new module has a `Steepfile`, and Steep in the `development` group of its
`Gemfile`, which the module's container does not install:

```sh
bundle install
bundle exec steep check
```

Steep reads `lib/` and its annotations, and checks them against `sdk/sig`
(the SDK), `clients/` (each client's signatures) and
`sdk/entrypoint/module.rbs`, which `dagger generate` writes: the readers and
initializer of each object's fields and the constants of each enum's members,
which `field` and `member` define when the file loads. So a function body
that returns another type than its annotation, or a call to a client with a
wrong argument, fails Steep.

The SDK module runs the same check from `dagger`, on every Ruby module of the
workspace, each in its own image with its `development` group installed, so the
host needs no Ruby:

```sh
dagger check                                     # every check, ruby-sdk:steep among them
dagger check ruby-sdk:steep                      # every module: generation's checks, then Steep
dagger call ruby-sdk mod --path <path> steep     # the module at or above <path>
```

A module is what generation wrote: a `dagger-module.toml` naming
`./sdk/entrypoint`, an `sdk/` marked by the SDK, and a `Gemfile`, wherever it
sits; the check reads no `dagger.toml`, so a module need not be registered. The
SDK module itself, plain scopes and other SDKs' modules are not modules here.

**What a passing check means.** `dagger generate` accepts every module the
check found, as it stands, with the clients it was last generated with, and
Steep passes on each that has a `Steepfile`. The check runs generation's own
refusals on each module, the same code: the scope's members and manifest,
Bundler on its `Gemfile`, and `dagger-mod entrypoint` on its annotations as
they are now, with every rule of the registry (a function or field without a
type, an annotation that does not parse or disagrees with its `def`, a type the
API cannot carry, a name like a client's method, and the rest). Steep alone
passes on a function without an annotation, which inline RBS takes as untyped,
and on a field without a type. A refusal comes in generation's own words:

```
.dagger/modules/my-module: dagger generate refuses it
.dagger/modules/my-module: describing the module failed: dagger-mod: Dagger::Mod::RegistrationError: lib/my_module.rb:31: MyModule.hello has no annotation that generation read; write its type on the line above the def, as #: (name: String) -> String
```

What it does not guarantee: anything about clients the scope declares in
`dagger.toml` since the last generation (a client name or method that clashes,
a git client without a pin), and what only the engine or the network decides at
generation (generating core and the clients, relocking). A `Gemfile` edited
without relocking fails the check's install while generation would relock it.
A module without a `Steepfile` gets generation's checks and no Steep.

Steep checks each module against the `module.rbs` generation would write, so a
field type edited since the last `dagger generate` is checked too. A failure
reports every failing module, each with generation's refusals and Steep's exit
code and own output; every run ends with what it checked:

```
The Steep check failed in 1 of 3 Ruby modules: steep-broken

steep-broken: bundle exec steep check exited 1
# Type checking files:
...
lib/steep_broken.rb:24:6: [error] Cannot allow method body have type `::Dagger::Clients::Core::Container` because declared as type `::String`
...
checked: .dagger/modules/e2e, steep-broken, steep-clean
generation checks ok: .dagger/modules/e2e, steep-broken, steep-clean
steep ok: steep-clean
steep skipped, no Steepfile: .dagger/modules/e2e
```

The template's `Steepfile` also makes two Steep diagnostics errors that match
generation's refusals: a parameter of another kind than its annotation's
(`Ruby::DifferentMethodParameterKind`) and a constant that names nothing
(`Ruby::UnknownConstant`). Neither asks anything of a helper method without an
annotation or of a reader. Steep has no diagnostic for a def or a field with no
annotation, so a helper method needs none.

The check installs the development group in a layer of its own, keyed on the
Gemfiles and gemspecs, so an edit to `lib/` reuses it; a module's own container
still installs without it.

RBS 4 and Steep 2 read the inline syntax natively; the `rbs-inline` gem that
first proposed it is deprecated. Their authors still mark the syntax
experimental, so the SDK pins the `rbs` it parses with: a new version is an
SDK update.

## Clients

```sh
cd hello
dagger module client add ../lib
```

This writes `clients/lib/`, a line of `dagger.gemfile` and the method `lib` of
`clients/roots/`, and relocks. No client reaches the manifest. A client loads
a module of the workspace by its path, also in a workspace opened from a git
ref. A plain program uses the long form, and a module the method:

```ruby
# main.rb, a plain program
require "dagger"
require "dagger/clients/lib"

puts Dagger::Clients::Lib.lib.greeting(name: "ruby")
```

```ruby
# lib/hello.rb, a module
require "dagger"
require "dagger/clients/roots"

class Hello
  extend Dagger::Mod::Object
  include Dagger::Clients::Roots

  function "Greet through lib."
  #: () -> String
  def hello = lib.greeting(name: "ruby")
end
```

A plain program may use the methods too: `include Dagger::Clients::Roots` in
one of its classes, or `extend Dagger::Clients::Roots` at the top level, which
gives them to top-level code alone.

A client loads its module through `serveModule` on first use, once per
session. A plain program in a scope (a directory with a `Gemfile`, registered
with `dagger module client add` from it) runs under `dagger run`, or starts
its own `dagger session` and stops it on exit:

```sh
bundle install
dagger run ruby -rbundler/setup main.rb
ruby -rbundler/setup main.rb
```

A client generated for another core than the scope's raises
`Dagger::StaleClientError`; so does a query to a field the module no longer
has. Both say to run `dagger generate`.

## When to run `dagger generate`

`dagger generate` regenerates every scope: the members, `dagger.gemfile`, the
lock, and for a module its entrypoint in `sdk/entrypoint/`. A module needs it
after a change to what it declares (a function, an argument, an annotation),
to its clients, or to its gems; an edit to a function's body runs at once.
Nothing checks that a module was regenerated: a module that needed it fails
with the error that Ruby, Bundler or the CLI gives, or with the method that no
longer takes what its annotation took, which `dagger-mod` and the build follow
with `if you changed declarations, clients or gems, run dagger generate`. A
function declared since the last generation is unknown to the engine, so
`dagger call` reports an unknown command instead.

A call builds the module's container from its current source. The gems
install from `Gemfile`, `Gemfile.lock`, `dagger.gemfile` and the path gems'
gemspecs alone, and the engine caches that step by their contents: an edit to
`lib/` reuses the installed gems.

## Gems outside the module

A module's Gemfile can name gems outside the module's directory, elsewhere in
its repository: `gem "shared", path: "../shared"`, a `path "../gems" do`
block, `gemspec path: "../tool"`, and the files it evaluates,
`eval_gemfile "../Gemfile.common"` and `ruby file: "../.ruby-version"`.

```ruby
# .dagger/modules/app/Gemfile
source "https://rubygems.org"

eval_gemfile "dagger.gemfile"

gem "shared", path: "../../../gems/shared"
```

`dagger generate` finds them in the Gemfile and in each file it evaluates, and
returns them from the entrypoint's `sources`, at their paths from the
workspace's root: the engine loads them with the module, from its checkout or
its git commit, and keys every call on them, so an edit to `gems/shared` gives
the next call a new result, and a file outside the module that `sources` does
not return leaves it as it was. The module then builds from its context
directory, where it sits beside them. Its gems install from
its Gemfiles and from the gems outside, by their contents: an edit to `lib/`
still reuses the installed gems, and an edit to a gem outside installs them
again (8 s for a module with one native extension).

- A path is a string literal, relative to the file that names it. Generation
  refuses an expression, an absolute path, a path that leaves the workspace's
  root or names nothing in it, and one whose files `.gitignore` all ignores,
  which the engine does not load; each refusal names the file and line, and
  the Steep check refuses the same.
- A gem's directory goes whole, but for its `.bundle` and `vendor/bundle`.
- Run `dagger generate` after changing which gems outside the module the
  Gemfile names: until then a call fails with Bundler's error and the hint.
- Only what the Gemfile names is loaded: a file that the module's code reads
  outside its directory, with `require_relative` or `File.read`, is not there.
- It needs an engine that evaluates the entrypoint's `sources`, which no
  schema field shows, and whose `CurrentModule` has `contextDirectory` and
  `sourceSubpath`, which generation checks: it refuses the module on an
  engine without them. Declaring `sources` changes the entrypoint's contract:
  `types` and `call` get no workspace. A module without gems outside its
  directory keeps the contract where they get one, and generates the same
  files as before.

## Errors

| Error | When |
| --- | --- |
| `Dagger::QueryError`, `Dagger::ExecError` | the API answers with errors; an `ExecError` carries the exit code, stdout and stderr |
| `Dagger::ConnectionError` | no session, and none can be started |
| `Dagger::ClientLoadError`, `Dagger::StaleClientError` | a client cannot load, or was generated for another core or module |
| `Dagger::Mod::RegistrationError` | a declaration or annotation is wrong; raised at generation, naming its file and line |
| `Dagger::Mod::FunctionError` | module code raised |

A function that raises fails its call. A calling module receives an
`ExecError` whose stderr holds the error.

## What the generated entrypoint cannot do

- Cache policies: `function cache:` is refused at generation.
- Structured errors: a caller sees the failed call and its stderr.
- An interface function returning a module object: return an interface instead.

## Known engine limitations

- A function that returns a nested list of scalars, `Array[Array[Integer]]`
  say, reaches its caller as rows of IDs instead of the values it returned
  (v1.0.0-beta.19). A nested list as an argument arrives intact, and a flat
  list of scalars comes back as returned.

## Versioning

The SDK is released by this repository's tags, which `dagger module install`
takes, and `CHANGELOG.md` records each release. A scope vendors the library
and its clients as path gems at `dagger generate`, so a module runs the SDK it
was generated with until it is generated again; nothing is published to
RubyGems.

## Contributing

`AGENTS.md` says how to work on this repository: its layout, the checks,
testing on a released or a custom engine, and refreshing the generated files.
`hack/designs/ruby-sdk-design.md` describes the design and its
decisions.
