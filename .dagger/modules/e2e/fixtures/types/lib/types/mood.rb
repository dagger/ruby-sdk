class Mood < Dagger::Mod::Enum
  description "How a value feels."
  member :HAPPY, "happy"
  member :CALM, "calm", doc: "The default."
  member :GRUMPY, "grumpy"
end
