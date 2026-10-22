#!/bin/sh
set -eu
. "$(dirname "$0")/engine.env"

fail() { echo "hack/engine.sh: $*" >&2; exit 1; }

case "${1:-}" in
start)
  # The released engine of the CLI's own version, so that the two match.
  version=$("$ruby_sdk_cli" version | sed -n 's/^version: *//p')
  [ -n "$version" ] || fail "$ruby_sdk_cli does not report its version"
  image=registry.dagger.io/engine:$version
  # A registry host, mirror.gcr.io say, that serves the engine's pulls from
  # docker.io, by the same digests: Docker Hub can throttle anonymous pulls.
  mirror=${RUBY_SDK_ENGINE_REGISTRY_MIRROR:-}
  running=$(docker inspect --format '{{.Config.Image}} {{index .Config.Labels "ruby-sdk.registry-mirror"}}' \
    "$ruby_sdk_engine" 2>/dev/null || true)
  if [ "$running" = "$image $mirror" ]; then
    docker start "$ruby_sdk_engine" >/dev/null
  else
    docker rm --force "$ruby_sdk_engine" >/dev/null 2>&1 || true
    # Another engine's cache would answer for this one with its own results:
    # each engine starts on an empty volume. A mirror changes no result.
    [ "${running%% *}" = "$image" ] || docker volume rm "$ruby_sdk_engine" >/dev/null 2>&1 || true
    set --
    if [ -n "$mirror" ]; then
      config=$HOME/.cache/ruby-sdk/engine.json
      mkdir -p "$(dirname "$config")"
      printf '{"registries": {"docker.io": {"mirrors": ["%s"]}}}\n' "$mirror" >"$config"
      set -- --volume "$config:/etc/dagger/engine.json:ro"
    fi
    docker run --detach --name "$ruby_sdk_engine" --privileged --label "ruby-sdk.registry-mirror=$mirror" \
      --volume "$ruby_sdk_engine:/var/lib/dagger" "$@" "$image" >/dev/null
  fi
  tries=0
  until "$0" check 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -lt 60 ] || fail "$ruby_sdk_engine started from $image does not answer"
    sleep 1
  done
  ;;
check)
  got=$(echo '{ version }' | "$ruby_sdk_cli" query | sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p')
  [ -n "$got" ] || fail "the engine at $DAGGER_ENGINE does not answer"
  echo "$got"
  ;;
remove)
  docker stop --timeout=-1 "$ruby_sdk_engine" 2>/dev/null || true
  docker rm -v "$ruby_sdk_engine" 2>/dev/null || true
  docker volume rm "$ruby_sdk_engine" 2>/dev/null || true
  rm -f "$HOME/.cache/ruby-sdk/engine.json"
  ;;
*) fail "usage: hack/engine.sh start | check | remove" ;;
esac
