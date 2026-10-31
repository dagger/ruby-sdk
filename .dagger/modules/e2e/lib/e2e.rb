require "securerandom"
require "json"
require "dagger"
require "dagger/clients/core"
require "dagger/clients/ruby_sdk"
require_relative "e2e/support"

class E2E
  extend Dagger::Mod::Object
  include Support

  description "End-to-end checks of the Ruby SDK, run by dagger check on the engine under test."
end

require_relative "e2e/scope_checks"
require_relative "e2e/dang_config_checks"
require_relative "e2e/module_checks"
require_relative "e2e/cli_checks"
require_relative "e2e/sdk_checks"
require_relative "e2e/client_checks"
require_relative "e2e/types_checks"
require_relative "e2e/annotation_checks"
require_relative "e2e/install_checks"
require_relative "e2e/roots_checks"
require_relative "e2e/collection_checks"
require_relative "e2e/sources_checks"
require_relative "e2e/plain_checks"
require_relative "e2e/git_workspace_checks"
require_relative "e2e/generators"
