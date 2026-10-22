class Badge
  extend Dagger::Mod::Object

  description "A module object passed as an argument. Not Pair: the engine cannot pass an object with an enum " \
              "field as an argument (\"cannot create enum name from dagql.Result\")."

  field :text #: String
  field :note, private: true, default: "noted" #: String
end
