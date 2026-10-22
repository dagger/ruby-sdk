#!/bin/sh
# Regenerates every generated file, after a change to the SDK or to the
# engine's schema: the schema fixture and the goldens, in the development
# image; then each scope (dagger generate) and the root's plain scope, which
# dagger generate skips.
set -eu
. "$(dirname "$0")/engine.env"
"$ruby_sdk_repo/hack/engine.sh" check >/dev/null
cd "$ruby_sdk_repo"
x=$ruby_sdk_excludes
# A dagger shell pipeline continues on the next line only after a trailing pipe.
"$ruby_sdk_cli" -c "directory |
    with-directory hack/tools \$(host | directory $ruby_sdk_repo/hack/tools) |
    with-file hack/dev.Dockerfile \$(host | file $ruby_sdk_repo/hack/dev.Dockerfile) |
    docker-build --dockerfile hack/dev.Dockerfile |
  with-directory /src \$(host | directory $ruby_sdk_repo --exclude $x) |
  with-workdir /src |
  with-exec -- ruby hack/refresh.rb |
  directory /src/test | filter --exclude $x |
  changes \$(host | directory $ruby_sdk_repo/test --exclude $x) | export $ruby_sdk_repo/test"
"$ruby_sdk_cli" generate -y
"$ruby_sdk_cli" -c 'ruby-sdk | generate-scope false "" "" | export'
