class Item
  extend Dagger::Mod::Object

  field :name #: String

  function "Fails for item:c only.", check: true
  #: () -> void
  def verify
    raise "item c fails its check" if name == "item:c"
  end
end
