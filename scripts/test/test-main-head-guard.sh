#!/usr/bin/env bash
#
# The deploy job is serialized, but builds are not: an older build can finish
# after a newer one and reach the deploy queue later. It must not replace the
# current main repository on Pages with stale content.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_PARENT="$REPO_ROOT/.tmp"
mkdir -p "$TEST_PARENT"
WORK="$(mktemp -d "$TEST_PARENT/main-head.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

STUBS="$WORK/stubs"
export STUB_LOG="$WORK/git.calls"
mkdir -p "$STUBS"
: > "$STUB_LOG"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf '  ok: %s\n' "$*"; }

cat > "$STUBS/git" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$STUB_LOG"
case "${STUB_GIT_MODE:-ok}" in
  fail) exit 1 ;;
  stale) printf '%s\n' 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb	refs/heads/main' ;;
  *) printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa	refs/heads/main' ;;
esac
STUB
chmod +x "$STUBS/git"
export PATH="$STUBS:$PATH"
export GITHUB_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

# --- scenario 1: the checked-out commit is still main ----------------------
echo "scenario: the current main commit is allowed to deploy"
bash "$REPO_ROOT/scripts/actions/is-main-head.sh" \
  || fail "the current main head must be allowed to deploy"
ok "current main head allowed"

# --- scenario 2: a queued older build is skipped ---------------------------
echo "scenario: a stale build is rejected before it can replace Pages"
if STUB_GIT_MODE=stale bash "$REPO_ROOT/scripts/actions/is-main-head.sh"; then
  fail "a stale build must not be allowed to deploy"
fi
ok "stale build rejected"

# --- scenario 3: a failed lookup is not mistaken for a stale build ----------
echo "scenario: a failed main-head lookup is an error, not a skip"
rc=0
STUB_GIT_MODE=fail bash "$REPO_ROOT/scripts/actions/is-main-head.sh" || rc=$?
assert_rc() { [[ "$1" == "$2" ]] || fail "$3 (expected $2, got $1)"; ok "$3"; }
assert_rc "$rc" 2 "lookup failure is distinguishable from a stale commit"

echo "PASS: Pages can only be replaced by the current main commit"
