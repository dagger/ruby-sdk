#!/bin/sh
# Runs the harness's checks on the dedicated engine, in a scratch copy of this
# tree, so that a check never writes into it: every check but clientCacheCheck
# and the SDK module's ruby-sdk:steep, or the named ones, then clientCacheCheck
# alone.
#
#   hack/e2e.sh                     # every check
#   hack/e2e.sh manifest-check ...  # the named checks, and clientCacheCheck
#
# E2E_SCRATCH names the copy; it defaults to one path that every run reuses.
# The copy is synced with --delete, so a directory that holds anything else
# than a copy this script made is refused.
set -eu
. "$(dirname "$0")/engine.env"
_EXPERIMENTAL_DAGGER_CLI_BIN=$ruby_sdk_cli
export _EXPERIMENTAL_DAGGER_CLI_BIN

version=$("$ruby_sdk_repo/hack/engine.sh" check)
module=.dagger/modules/e2e
scratch=${E2E_SCRATCH:-$HOME/.cache/ruby-sdk/e2e}
if [ -e "$scratch" ] && [ -n "$(ls -A "$scratch")" ] &&
  [ "$(git --git-dir="$scratch/.git" config --get ruby-sdk.e2e-scratch 2>/dev/null)" != true ]; then
  echo "hack/e2e.sh: $scratch is not empty and is no copy of hack/e2e.sh; name another E2E_SCRATCH" >&2
  exit 1
fi
mkdir -p "$scratch"
rsync -a --delete --exclude .git --exclude vendor/bundle --exclude .bundle --exclude "/$module/out" \
  --exclude "/$module/cli" "$ruby_sdk_repo/" "$scratch/"
cd "$scratch"
git init --quiet
git config ruby-sdk.e2e-scratch true
quiet() {
  "$ruby_sdk_cli" "$@" >"$scratch.generate.log" 2>&1 ||
    { tail -20 "$scratch.generate.log" >&2; echo "hack/e2e.sh: dagger $1 failed ($scratch.generate.log)" >&2; exit 1; }
}
generate() { quiet generate -y; }
root_scope='ruby-sdk | generate-scope false "" "" | export'
# What the repository commits must be what generation writes. dagger generate
# skips the root plain scope, which holds the SDK module's own core: it is
# generated explicitly, so that a stale root core fails here too.
git add --all
git -c user.name=e2e -c user.email=e2e@dagger.io commit --quiet --allow-empty --no-gpg-sign --no-verify --message committed
generate
quiet -c "$root_scope"
stale=$(git status --porcelain)
[ -z "$stale" ] || {
  printf '%s\n' "$stale" >&2
  echo "hack/e2e.sh: the committed generated files are stale; run dagger generate, then dagger -c '$root_scope'" >&2
  exit 1
}
# The fixtures are committed as sources: register and generate them here, one
# scope per pass, since the engine sends every path a generation changes in one
# header, which several new scopes overflow.
scopes=$(mktemp -d)
awk -v dir="$scopes" '/^\[sdks\.ruby\.scopes\."/ { split($0, p, "\""); if (p[2] != scope) { scope = p[2]; n++ } }
  n { print >(dir "/" sprintf("%02d", n)) }' "$module/fixtures/scopes.toml"
for scope in "$scopes"/*; do
  cat "$scope" >>dagger.toml
  generate
done
rm -r "$scopes"
# The harness reaches the SDK module through a client, whose changes an engine
# without dagger/dagger#14491 does not see: the stamp is part of the harness's
# source. A custom engine's cache can outlive its rebuild: the copy's
# path and the engine's version are stamped too.
{
  echo "$scratch $version"
  # Split on purpose: one path per line, none with a space.
  find $(ruby_sdk_module_files) -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
} | sha256sum | cut -d" " -f1 >"$module/sdk.digest"
mkdir -p "$module/cli"
cp "$ruby_sdk_cli" "$module/cli/dagger"
# A fresh nonce, so that clientCacheCheck runs every time.
od -An -N8 -tx1 /dev/urandom | tr -d " \n" >"$module/cli/run"
echo "checks of $module in $scratch on $version, sdk.digest $(cat "$module/sdk.digest")" >&2

set +e
# The SDK module's own Steep check would take the fixtures for modules: their
# generation gives them the template's Steepfile, but they are not written for
# Steep. modulesSteepCheck runs that check on modules that are.
"$ruby_sdk_cli" check -m "$module" --skip client-cache-check --skip ruby-sdk:steep "$@"
checks=$?
log="$scratch.client-cache.log"
"$ruby_sdk_cli" --progress=plain -vvv check -m "$module" client-cache-check >"$log" 2>&1
cache=$?
set -e
lines=$(grep -oE 'clientCacheCheck [a-z-]+: (ok|FAIL[^"\\]*)' "$log" | awk '!seen[$0]++')
echo "$lines" >&2

echo "checks: exit $checks on $version" >&2
echo "clientCacheCheck: exit $cache on $version ($log)" >&2
[ "$checks" -eq 0 ] && [ "$cache" -eq 0 ]
