#!/usr/bin/env bash
#
# Offline suite for scripts/actions/auto-merge-dependabot.sh.
#
# `gh pr merge --auto` cannot be used here: GitHub only offers auto-merge on a
# branch whose protection rules require checks, and main has no protection
# rules because the daily updater pushes to it directly ("Protected branch
# rules not configured for this branch"). The script therefore waits for the
# checks the PR triggers and merges itself, which these scenarios pin down.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_PARENT="$REPO_ROOT/.tmp"
mkdir -p "$TEST_PARENT"
WORK="$(mktemp -d "$TEST_PARENT/auto-merge.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

STUBS="$WORK/stubs"
export STUB_LOG="$WORK/log"
mkdir -p "$STUBS" "$STUB_LOG"
: > "$STUB_LOG/gh.calls"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf '  ok: %s\n' "$*"; }

cat > "$STUBS/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$STUB_LOG/gh.calls"

case "${1:-} ${2:-}" in
  "pr review")
    [[ "${STUB_APPROVE:-ok}" == "ok" ]] || { echo "approve refused" >&2; exit 1; }
    ;;
  "pr checks")
    watch=0
    for arg in "$@"; do
      [[ "$arg" == "--watch" ]] && watch=1
    done
    if [[ "${STUB_CHECKS:-present}" == "missing" ]]; then
      echo "no checks reported on the 'dependabot/github_actions/github-actions' branch" >&2
      exit 1
    fi
    if [[ "$watch" == 1 ]]; then
      if [[ "${STUB_CHECKS:-present}" == "failing" ]]; then
        echo "X  Build & Validate Flatpak  8m  1 failing check"
        exit 1
      fi
      echo "Build & Validate Flatpak  pass"
    else
      printf '2\n'
    fi
    ;;
  "pr merge")
    printf '%s\n' "$*" > "$STUB_LOG/merged"
    ;;
esac
exit 0
STUB

chmod +x "$STUBS/gh"
export PATH="$STUBS:$PATH"

PR_URL="https://github.com/anthony1x6000/io.filen.desktop/pull/42"

run_script() { # env... -> runs the real script against the stubs
  ( CHECKS_WAIT_ATTEMPTS=2 POLL_SECONDS=0 env "$@" \
      bash "$REPO_ROOT/scripts/actions/auto-merge-dependabot.sh" "$PR_URL" ) \
    > "$WORK/out.log" 2>&1
}

# --- scenario 1: green checks, the PR is merged ---------------------------
echo "scenario: green checks merge the PR"
: > "$STUB_LOG/gh.calls"
rm -f "$STUB_LOG/merged"
run_script || { cat "$WORK/out.log" >&2; fail "green checks must merge the PR"; }
grep -q '^pr review --approve' "$STUB_LOG/gh.calls" || fail "the PR should be approved first"
grep -q '^pr merge .*--rebase --delete-branch' "$STUB_LOG/gh.calls" \
  || { cat "$WORK/out.log" >&2; fail "the merge must be a rebase merge that deletes the branch"; }
grep -q -- '--auto' "$STUB_LOG/gh.calls" && fail "auto-merge is unavailable without branch protection"
ok "green checks merged with --rebase --delete-branch"

# --- scenario 2: a failing check blocks the merge -------------------------
echo "scenario: a failing check keeps the PR open"
: > "$STUB_LOG/gh.calls"
if run_script STUB_CHECKS=failing; then
  fail "a failing check must not be merged"
fi
grep -q '^pr merge' "$STUB_LOG/gh.calls" && fail "nothing may be merged while a check fails"
ok "failing check blocked the merge"

# --- scenario 3: no checks ever appear ------------------------------------
echo "scenario: a PR without checks does not hang forever"
: > "$STUB_LOG/gh.calls"
if run_script STUB_CHECKS=missing; then
  fail "a PR that never reports checks must not be merged"
fi
grep -q 'no checks appeared' "$WORK/out.log" \
  || { cat "$WORK/out.log" >&2; fail "the failure must say no checks appeared"; }
grep -q '^pr merge' "$STUB_LOG/gh.calls" && fail "nothing may be merged without checks"
ok "missing checks failed the run instead of merging blind"

# --- scenario 4: an approval refusal does not block the merge -------------
echo "scenario: an approval GitHub refuses does not stop the merge"
: > "$STUB_LOG/gh.calls"
run_script STUB_APPROVE=refused || { cat "$WORK/out.log" >&2; fail "a refused approval must not block the merge"; }
grep -q '^pr merge' "$STUB_LOG/gh.calls" || fail "the merge must still happen"
ok "refused approval tolerated"

echo "PASS: dependabot PRs merge themselves once their checks are green"
