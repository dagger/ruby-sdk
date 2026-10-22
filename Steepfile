D = Steep::Diagnostic

target :sdk do
  signature "sdk/sig"
  check "sdk/lib"
  library "json", "net-http", "uri", "socket", "timeout", "fileutils", "digest", "open3"
  configure_code_diagnostics(D::Ruby.default)
end

target :core do
  signature "tmp/codegen/core/sig", "sdk/sig"
  check "tmp/codegen/core/lib"
  library "json", "net-http", "uri", "socket", "timeout", "fileutils", "digest", "open3"
  configure_code_diagnostics(D::Ruby.default)
end

target :client do
  signature "tmp/codegen/greeter/sig", "tmp/codegen/core/sig", "sdk/sig"
  check "tmp/codegen/greeter/lib"
  library "json", "net-http", "uri", "socket", "timeout", "fileutils", "digest", "open3"
  configure_code_diagnostics(D::Ruby.default)
end

target :roots do
  signature "tmp/codegen/roots/sig", "tmp/codegen/greeter/sig", "tmp/codegen/core/sig", "sdk/sig"
  check "tmp/codegen/roots/lib"
  library "json", "net-http", "uri", "socket", "timeout", "fileutils", "digest", "open3"
  configure_code_diagnostics(D::Ruby.default)
end

target :sdk_module do
  signature "sig", "sdk/sig", "tmp/codegen/core/sig"
  check "lib"
  library "json", "net-http", "uri", "socket", "timeout", "fileutils", "digest", "open3", "rbs", "prism"
  configure_code_diagnostics(D::Ruby.default)
end
