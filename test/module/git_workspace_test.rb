require_relative "../test_helper"
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "ruby_sdk/git_workspace"

class GitWorkspaceTest < Minitest::Test
  SHA = "419c4afea78603265c40e273c455623a0291922e".freeze
  OTHER = ("0" * 40).freeze
  CLONE = "http://h/r.git".freeze
  GITHUB = "https://github.com/o/r".freeze

  # The cases of dagger/python-sdk's workspaceRefMatchCheck: address, commit,
  # clone ref, ref, pin, and whether the module is the workspace's.
  CASES = {
    "the workspace at the commit" => ["#{CLONE}@#{SHA}", SHA, CLONE, "#{CLONE}/app@#{SHA}", SHA, true],
    "a workspace without a selector" => [CLONE, SHA, CLONE, "#{CLONE}/app@main", SHA, true],
    "a workspace in a subdirectory" => ["#{CLONE}/ci@main", SHA, CLONE, "#{CLONE}/app@main", SHA, true],
    "another selector at the same commit" => ["#{CLONE}@main", SHA, CLONE, "#{CLONE}/app@release", SHA, false],
    "another commit" => ["#{CLONE}@main", OTHER, CLONE, "#{CLONE}/app@main", SHA, false],
    "another repository" => ["#{CLONE}-fork@#{SHA}", SHA, CLONE, "#{CLONE}/app@#{SHA}", SHA, false],
    "an unknown workspace commit" => ["#{CLONE}@#{SHA}", "", CLONE, "#{CLONE}/app@#{SHA}", SHA, false],
    "a module without a pin" => ["#{CLONE}@#{SHA}", SHA, CLONE, "#{CLONE}/app@#{SHA}", "", false],
    "a GitHub address without a scheme" => ["github.com/o/r@#{SHA}", SHA, GITHUB, "#{GITHUB}/app@#{SHA}", SHA, true],
    "another host without a scheme" => ["gitlab.com/o/r@#{SHA}", SHA, GITHUB, "#{GITHUB}/app@#{SHA}", SHA, false],
    "a repository the clone ref is a prefix of" =>
      ["github.com/o/r2@#{SHA}", SHA, GITHUB, "#{GITHUB}2/app@#{SHA}", SHA, false],
    "the explicit form at the commit" => ["#{CLONE}@#{SHA}", SHA, CLONE, "#{CLONE}##{SHA}:app", SHA, true],
    "the explicit form on GitHub" => ["github.com/o/r@#{SHA}", SHA, GITHUB, "#{GITHUB}##{SHA}:app", SHA, true],
    "the explicit form at the repository root" =>
      ["github.com/o/r@#{SHA}", SHA, GITHUB, "#{GITHUB}##{SHA}", SHA, true],
    "the explicit form at a branch" => ["#{CLONE}@main", SHA, CLONE, "#{CLONE}#main:app", SHA, true],
    "the explicit form at another selector" => ["#{CLONE}@main", SHA, CLONE, "#{CLONE}#release:app", SHA, false],
    "the explicit form in another repository" =>
      ["github.com/o/r@#{SHA}", SHA, "#{GITHUB}-fork", "#{GITHUB}-fork##{SHA}:app", SHA, false],
    "the explicit form in a repository the clone ref is a prefix of" =>
      ["github.com/o/r@#{SHA}", SHA, GITHUB, "#{GITHUB}2##{SHA}:app", SHA, false]
  }.freeze

  def test_a_module_of_the_workspace_is_in_its_repository_at_its_commit_and_selector
    CASES.each do |name, (address, commit, clone_ref, ref, pin, want)|
      assert_equal want, RubySdk::GitWorkspace.matches?(address:, commit:, clone_ref:, ref:, pin:), name
    end
  end
end
