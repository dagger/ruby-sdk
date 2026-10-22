class App
  Greeting = Struct.new(:word) do
    def to(name) = "#{word}, #{name}!"
  end
end
