require "dagger"
require "dagger/clients/core"
require "dagger/clients/dep"
require_relative "types/mood"
require_relative "types/pair"
require_relative "types/badge"
require_relative "types/greeter"

class Types
  extend Dagger::Mod::Object

  description "Every row of the type mapping, called through dagger call by typesRoundTripCheck and errorCheck."

  field :build, default: "",
                doc: "Passed by the checks, so that one engine build never answers for another." #: String

  function "A string, back unchanged."
  #: (text: String) -> String
  def echo(text:) = text

  function "An integer, plus one."
  #: (number: Integer) -> Integer
  def succ(number:) = number + 1

  function "A float, halved."
  #: (number: Float) -> Float
  def half(number:) = number / 2

  function "A boolean, negated.", name: "negate"
  #: (flag: bool) -> bool
  def negate?(flag:) = !flag

  function "Nothing."
  #: () -> void
  def nothing = nil

  function "An optional string: the same, or null."
  #: (text: String?) -> String?
  def maybe(text:) = text

  function "A list, reversed."
  #: (items: Array[String]) -> Array[String]
  def reversed(items:) = items.reverse

  function "A nested list as an argument, flattened."
  #: (rows: Array[Array[Integer]]) -> Array[Integer]
  def flatten(rows:) = rows.flatten

  function "The next mood; the default is a member."
  #: (?mood: Mood) -> Mood
  def next_mood(mood: Mood::CALM)
    members = Mood.dagger_members
    members[(members.index(mood) + 1) % members.size]
  end

  function "A module object as a result."
  #: (left: String, right: String, ?mood: Mood) -> Pair
  def pair(left:, right:, mood: Mood::HAPPY) = Pair.new(left:, right:, mood:)

  function "A module object as a result, to pass on."
  #: (text: String) -> Badge
  def badge(text:) = Badge.new(text:)

  function "A module object as an argument, its private field included."
  #: (badge: Badge) -> String
  def read(badge:) = "#{badge.text}/#{badge.note}"

  function "Module objects as a list."
  #: (names: Array[String]) -> Array[Pair]
  def pairs(names:) = names.each_cons(2).map { |left, right| Pair.new(left:, right:) }

  function "The dep client's object, as an interface."
  #: () -> Greeter
  def greeter = Dagger::Clients::Dep.dep

  function "An interface as an argument, called through its binding."
  #: (greeter: Greeter, name: String) -> String
  def greet_with(greeter:, name:) = "through the interface: #{greeter.greeting(name:)}"

  function "Interfaces as a list."
  #: () -> Array[Greeter]
  def greeters = [Dagger::Clients::Dep.dep, Dagger::Clients::Dep.dep]

  function "A core object in, a scalar out."
  #: (file: Dagger::Clients::Core::File) -> Integer
  def size(file:) = file.size

  function "A core object out."
  #: (contents: String) -> Dagger::Clients::Core::File
  def write(contents:)
    Dagger::Clients::Core.core.directory.with_new_file(path: "out.txt", contents:).file(path: "out.txt")
  end

  function "A core scalar in and out."
  #: (value: Dagger::Clients::Core::JSON) -> Dagger::Clients::Core::JSON
  def json(value:) = Dagger::Clients::Core::JSON.new(JSON.generate("echo" => JSON.parse(value)))

  function "A core enum in and out."
  #: (protocol: Dagger::Clients::Core::NetworkProtocol) -> Dagger::Clients::Core::NetworkProtocol
  def other_protocol(protocol:)
    protocols = Dagger::Clients::Core::NetworkProtocol
    protocol == protocols::TCP ? protocols::UDP : protocols::TCP
  end

  function "Defaults of every scalar kind."
  #: (?name: String, ?times: Integer, ?ratio: Float, ?loud: bool) -> String
  def defaults(name: "world", times: 2, ratio: 0.5, loud: false) = "#{loud ? name.upcase : name} #{times} #{ratio}"

  function "A directory passed by the caller, without what ignore names."
  arg :dir, ignore: %w[lib sdk clients]
  #: (dir: Dagger::Clients::Core::Directory) -> Array[String]
  def entries(dir:) = dir.entries

  function "Raises, so the call fails."
  #: (message: String) -> void
  def explode(message:) = raise(ArgumentError, message)

  function "An ExecError from the API, rescued: its exit code and stderr."
  #: () -> String
  def exec_error
    Dagger::Clients::Core.core.container.from(address: "alpine:3.24")
                         .with_exec(args: ["sh", "-c", "echo out; echo oops >&2; exit 3"]).stdout
    "no error"
  rescue Dagger::ExecError => e
    "exit=#{e.exit_code} stderr=#{e.stderr.strip}"
  end
end
