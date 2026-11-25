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
export GITHUB_OUTPUT="$WORK/github-output"

run_check() { # extra env via caller
  : > "$GITHUB_OUTPUT"
  bash "$REPO_ROOT/scripts/actions/check-pages-head.sh"
}

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

# --- scenario 4: the workflow wrapper publishes output only for main -------
echo "scenario: the workflow wrapper marks the current head deployable"
run_check || fail "the current main head must produce deploy=true"
grep -qx 'deploy=true' "$GITHUB_OUTPUT" || fail "current head output missing"
ok "workflow wrapper marked the current head deployable"

# --- scenario 5: a stale head fails the watched run instead of succeeding ----
echo "scenario: the workflow wrapper fails a stale deployment"
: > "$GITHUB_OUTPUT"
rc=0
STUB_GIT_MODE=stale run_check || rc=$?
assert_rc "$rc" 1 "stale deployment fails the watched job"
[[ -s "$GITHUB_OUTPUT" ]] && fail "stale head must not be marked deployable"
ok "stale deployment cannot be reported as shipped"

# --- scenario 6: lookup errors remain errors ---------------------------------
echo "scenario: the workflow wrapper preserves lookup errors"
rc=0
STUB_GIT_MODE=fail run_check || rc=$?
assert_rc "$rc" 2 "workflow wrapper preserves lookup failure"

echo "PASS: Pages can only be replaced by the current main commit"
