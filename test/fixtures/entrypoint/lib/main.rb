class Color < Dagger::Mod::Enum
  description "A color."
  member :RED, "red", doc: "The red one."
  member :BLUE, "blue"
end

class Helper
  extend Dagger::Mod::Object

  description "A helper."
  field :level, doc: "A color." #: Color
end

class Main
  extend Dagger::Mod::Object

  description "The main object."
  field :greeting, default: "hello" #: String
  field :how_many, default: 1, doc: "How many" #: Integer
  field :source, private: true, ignore: ["vendor"] #: ModHelper::Core::Directory

  function "A \"container\".\n\nBuilt from\\a base image.\tTabbed."
  #: (?from: String) -> String
  def container(from: "alpine") = from

  function check: true
  #: () -> void
  def lint = nil

  function generator: true, start: true, agent: true, deprecated: "use container"
  arg :color, doc: "Which one"
  #: (who: String?, ?color: Color) -> Array[Helper]
  def mob(who:, color: Color::BLUE) = [who, color]

  function name: "isReady"
  #: () -> bool
  def ready? = true
end
