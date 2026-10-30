require "dagger"

class RubySdk
  # A workspace opened from git resolves its own modules as git sources at
  # its commit: bound by that ref, a client would change with every commit
  # and never match what the checkout generates, so it is bound by path. The
  # Go and Python SDKs bind by the same rule (dagger/go-sdk#73, #78, #79;
  # dagger/python-sdk#64, #65).
  module GitWorkspace
    module_function

    def includes?(ws, client)
      matches?(address: ws.address, commit: commit(ws), clone_ref: client.clone_ref, ref: client.as_string,
               pin: client.pin)
    end

    # An unknown commit matches no client, which keeps its git binding.
    def commit(ws)
      ws.git.head.commit
    rescue Dagger::QueryError
      ""
    end

    # A workspace without a selector resolves its modules at the default
    # branch, which its address does not name. Selectors compare as written,
    # so an alias, HEAD for main say, keeps the git binding.
    def matches?(address:, commit:, clone_ref:, ref:, pin:)
      return false if clone_ref.empty? || pin.empty? || pin != commit

      workspace_selector = selector(address, clone_ref) or return false
      module_selector = selector(ref, clone_ref) or return false
      workspace_selector.empty? || workspace_selector == module_selector
    end

    # A workspace's address reads <clone>/<path>@<version>; from engine
    # v1.0.0-beta.20 a module's ref reads <clone>#<version>[:<path>]. A GitHub
    # address has no URL scheme, while its clone ref has https://.
    def selector(ref, clone_ref)
      repository = clone_ref.sub(%r{\A.*?://}, "")
      path = ref.sub(%r{\A.*?://}, "")
      return nil unless path.start_with?(repository)

      rest = path.delete_prefix(repository)
      return rest.delete_prefix("#").partition(":").first if rest.start_with?("#")

      rest.empty? || rest.start_with?("/", "@") ? rest.partition("@").last : nil
    end
  end
end
