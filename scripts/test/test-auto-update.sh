#!/usr/bin/env bash
#
# Offline regression test for scripts/actions/auto-update.sh.
#
# The daily workflow broke because flatpak-external-data-checker (FEDC) commits
# its edits by itself after --update, and its sanitised git environment cannot
# commit inside the container ("Author identity unknown" -> exit 128). That
# killed the run before the release was ever cut.
#
# flatpak, gh and the flatpak build are stubbed here, no network or flatpak
# runtime needed. The FEDC stub reproduces that same commit failure whenever it
# is not told --edit-only, so the suite proves the script keeps FEDC in
# edit-only mode and owns commit/tag/release itself.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_PARENT="$REPO_ROOT/.tmp"
mkdir -p "$TEST_PARENT"
WORK="$(mktemp -d "$TEST_PARENT/auto-update.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Keep every `git config --global` write inside the sandbox and start with no
# identity anywhere, exactly like the workflow container.
export GIT_CONFIG_GLOBAL="$WORK/global.gitconfig"
: > "$GIT_CONFIG_GLOBAL"
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

export GITHUB_TOKEN=dummy-token
export GH_TOKEN=dummy-token

STUBS="$WORK/stubs"
export STUB_LOG="$WORK/log"
export STUB_RELEASES="$WORK/releases"
export STUB_FEDC_HOME="$WORK/fedc-home"
mkdir -p "$STUBS" "$STUB_LOG" "$STUB_RELEASES" "$STUB_FEDC_HOME"
: > "$STUB_LOG/fedc.calls"
: > "$STUB_LOG/gh.calls"
: > "$STUB_LOG/build.calls"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf '  ok: %s\n' "$*"; }

assert_eq() { # expected actual message
  [[ "$1" == "$2" ]] || fail "$3 (expected '$1', got '$2')"
  ok "$3"
}

# --- flatpak stub: emulates FEDC, including its broken commit path -----------
cat > "$STUBS/flatpak" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
# remote-add / install are not interesting
[[ "${1:-}" == "run" ]] || exit 0
shift

manifest=""
edit_only=0
for arg in "$@"; do
  case "$arg" in
    --edit-only) edit_only=1 ;;
    --update|org.flathub.flatpak-external-data-checker|--env=*|--filesystem=*) ;;
    -*) ;;
    *) manifest="$arg" ;;
  esac
done
printf '%s\n' "$*" >> "$STUB_LOG/fedc.calls"

[[ -n "$manifest" && -f "$manifest" ]] || { echo "stub FEDC: manifest not found" >&2; exit 2; }

current="$(grep -oP 'releases/download/v\K[^/]+' "$manifest" | head -n 1)"
[[ "$current" == "$STUB_LATEST_VERSION" ]] && exit 0

python3 - "$manifest" "$STUB_LATEST_VERSION" <<'PY'
import pathlib, re, sys
path, latest = pathlib.Path(sys.argv[1]), sys.argv[2]
text = path.read_text()
text = re.sub(r'releases/download/v[^/]+/', f'releases/download/v{latest}/', text)
text = re.sub(r'(sha256: )[0-9a-f]{64}', r'\g<1>' + 'f' * 64, text)
path.write_text(text)
PY

[[ "$edit_only" == 1 ]] && exit 0

# What FEDC does without --edit-only: commit with a sanitised environment.
# Fails the same way it does in the container, killing the whole run.
env -i PATH="/usr/bin:/bin" HOME="$STUB_FEDC_HOME" \
  git commit --no-verify --no-gpg-sign -am "filen: Update to $STUB_LATEST_VERSION"
STUB

# --- gh stub: records release publishing ------------------------------------
cat > "$STUBS/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$STUB_LOG/gh.calls"
case "${1:-} ${2:-}" in
  "release view")
    [[ -f "$STUB_RELEASES/${3:-}" ]] || exit 1
    ;;
  "release create")
    : > "$STUB_RELEASES/${3:-}"
    ;;
esac
exit 0
STUB

chmod +x "$STUBS/flatpak" "$STUBS/gh"
export PATH="$STUBS:$PATH"

new_workspace() { # $1 name -> prints workspace path, seeds a bare remote
  local root="$WORK/$1"
  mkdir -p "$root"
  git init -q --bare -b main "$root/remote.git"
  git clone -q "$root/remote.git" "$root/ws"
  cp -a "$REPO_ROOT/io.filen.desktop.yaml" \
        "$REPO_ROOT/io.filen.desktop.metainfo.xml" \
        "$REPO_ROOT/scripts" "$root/ws/"
  cat > "$root/ws/scripts/build/build-flatpak.sh" <<'BUILD'
#!/usr/bin/env bash
set -euo pipefail
echo "bespoke build" >> "$STUB_LOG/build.calls"
: > io.filen.desktop.flatpak
BUILD
  git -C "$root/ws" -c user.name=seed -c user.email=seed@example.com add -A
  git -C "$root/ws" -c user.name=seed -c user.email=seed@example.com \
    commit -q -m "seed"
  git -C "$root/ws" push -q origin main
  printf '%s\n' "$root"
}

run_update() { # $1 workspace -> runs the real script, logs to $WORK/last.log
  if ( cd "$1" && bash scripts/actions/auto-update.sh ) > "$WORK/last.log" 2>&1; then
    return 0
  fi
  echo "--- auto-update.sh output ---" >&2
  cat "$WORK/last.log" >&2
  return 1
}

remote_tag_list() { git --git-dir="$1/remote.git" tag --list; }
remote_commits() { git --git-dir="$1/remote.git" rev-list --count main; }

# --- scenario 1: upstream released a new version ----------------------------
echo "scenario: new upstream release is packaged, tagged and published"
export STUB_LATEST_VERSION=9.9.9
root="$(new_workspace new-release-main)"
run_update "$root/ws" || fail "auto-update.sh must succeed without FEDC's own commit"

assert_eq "9.9.9" \
  "$(grep -oP 'releases/download/v\K[^/]+' "$root/ws/io.filen.desktop.yaml" | head -n 1)" \
  "manifest bumped to the new upstream version"
assert_eq "2" "$(remote_commits "$root")" "exactly one release commit was pushed"
assert_eq "33004321+anthony1x6000@users.noreply.github.com" \
  "$(git --git-dir="$root/remote.git" log -1 --format=%ae main)" \
  "release commit uses the repository identity"
assert_eq "v9.9.9" "$(remote_tag_list "$root")" "release tag pushed"
assert_eq "1" "$(grep -c 'release view v9.9.9' "$STUB_LOG/gh.calls")" \
  "release existence is checked before publishing"
[[ -f "$STUB_RELEASES/v9.9.9" ]] || fail "release v9.9.9 was never published"
ok "release v9.9.9 published with the bundle"
grep -q 'version="9.9.9"' "$root/ws/io.filen.desktop.metainfo.xml" \
  || fail "metainfo.xml has no 9.9.9 release entry"
ok "metainfo.xml documents the new release"
grep -q -- '--edit-only' "$STUB_LOG/fedc.calls" \
  || fail "FEDC must run with --edit-only, otherwise it commits on its own"
ok "FEDC runs in --edit-only mode"

# --- scenario 2: nothing new upstream --------------------------------------
echo "scenario: no upstream release leaves the repo untouched"
export STUB_LATEST_VERSION="$(grep -oP 'releases/download/v\K[^/]+' "$root/ws/io.filen.desktop.yaml" | head -n 1)"
before_commits="$(remote_commits "$root")"
: > "$STUB_LOG/gh.calls"
: > "$STUB_LOG/build.calls"
run_update "$root/ws" || fail "auto-update.sh must exit cleanly when nothing changed"
assert_eq "$before_commits" "$(remote_commits "$root")" "no extra commit on rerun"
assert_eq "" "$(cat "$STUB_LOG/build.calls")" "no wasted flatpak build"
grep -q 'release create' "$STUB_LOG/gh.calls" && fail "no release must be created"
ok "no release published"

# --- scenario 3: bump landed but tagging/releasing died --------------------
echo "scenario: half-finished run is completed on the next run"
git --git-dir="$root/remote.git" tag -d v9.9.9 > /dev/null
git -C "$root/ws" tag -d v9.9.9 > /dev/null
rm -f "$STUB_RELEASES/v9.9.9"
: > "$STUB_LOG/build.calls"
run_update "$root/ws" || fail "auto-update.sh must complete an interrupted release"

assert_eq "$before_commits" "$(remote_commits "$root")" "no duplicate release commit"
assert_eq "v9.9.9" "$(remote_tag_list "$root")" "missing tag recreated"
[[ -f "$STUB_RELEASES/v9.9.9" ]] || fail "missing release was never published"
ok "release recreated from the already-bumped manifest"

echo "PASS: auto-update.sh packages releases without relying on FEDC's commit"
