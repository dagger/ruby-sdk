require_relative "mood"

class Pair
  extend Dagger::Mod::Object

  description "A module object, as an argument, a result and state."

  field :left #: String
  field :right #: String
  field :mood, default: Mood::CALM #: Mood
  field :hidden, private: true, default: "kept" #: String

  function "The pair the other way round; its state, the private field included, survives."
  #: () -> Pair
  def swapped = Pair.new(left: right, right: left, mood:, hidden:)

  function "The private field, read back from state."
  #: () -> String
  def secret = hidden
end
