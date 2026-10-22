require_relative "shared/version"

module Shared
  def self.word = File.read(File.join(__dir__, "shared/word.txt")).strip
end
