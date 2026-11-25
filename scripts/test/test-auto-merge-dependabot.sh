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
export GITHUB_REPOSITORY="anthony1x6000/io.filen.desktop"
mkdir -p "$STUBS" "$STUB_LOG"
: > "$STUB_LOG/gh.calls"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf '  ok: %s\n' "$*"; }

cat > "$STUBS/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$STUB_LOG/gh.calls"

emit() { # $1 json -> applies the --jq expression the caller asked for
  local expr="" prev="" arg
  for arg in "$@"; do
    [[ "$prev" == "--jq" ]] && expr="$arg"
    prev="$arg"
  done
  if [[ -n "$expr" ]]; then
    printf '%s' "$1" | jq -r "$expr"
  else
    printf '%s\n' "$1"
  fi
}

case "${1:-} ${2:-}" in
  "pr review")
    [[ "${STUB_APPROVE:-ok}" == "ok" ]] || { echo "approve refused" >&2; exit 1; }
    ;;
  "pr view")
    views=$(cat "$STUB_LOG/pr-views" 2>/dev/null || echo 0)
    views=$((views + 1))
    printf '%s\n' "$views" > "$STUB_LOG/pr-views"
    sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    if [[ "${STUB_HEAD_CHANGED:-0}" == 1 && "$views" -gt 1 ]]; then
      sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    fi
    emit '{"headRefOid":"'"$sha"'"}' "$@"
    ;;
  "api "*)
    case "$2" in
      *"/check-runs")
        polls=$(cat "$STUB_LOG/polls" 2>/dev/null || echo 0)
        polls=$((polls + 1))
        printf '%s\n' "$polls" > "$STUB_LOG/polls"
        self='{"name":"Auto-merge Dependabot PRs","status":"in_progress","conclusion":null}'
        case "${STUB_CHECKS:-present}" in
          missing) runs="[$self]" ;;
          failing) runs='[{"name":"Build & Validate Flatpak","status":"completed","conclusion":"failure"},'"$self"']' ;;
          pending)
            if [[ "$polls" == 1 ]]; then
              runs='[{"name":"Build & Validate Flatpak","status":"in_progress","conclusion":null},'"$self"']'
            else
              runs='[{"name":"Build & Validate Flatpak","status":"completed","conclusion":"success"},'"$self"']'
            fi
            ;;
          *) runs='[{"name":"Build & Validate Flatpak","status":"completed","conclusion":"success"},'"$self"']' ;;
        esac
        emit '{"total_count":2,"check_runs":'"$runs"'}' "$@"
        ;;
    esac
    ;;
  "pr checks")
    # Real gh exits 8 while any check is pending, including this workflow's
    # own check. A script that uses this command can never see all-green.
    printf '2\n'
    exit 8
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
OLD_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

run_script() { # env... -> runs the real script against the stubs
  ( CHECKS_WAIT_ATTEMPTS=2 POLL_SECONDS=0 env "$@" \
      bash "$REPO_ROOT/scripts/actions/auto-merge-dependabot.sh" "$PR_URL" ) \
    > "$WORK/out.log" 2>&1
}

reset_state() {
  : > "$STUB_LOG/gh.calls"
  rm -f "$STUB_LOG/merged" "$STUB_LOG/pr-views" "$STUB_LOG/polls"
}

# --- scenario 1: green checks merge, without waiting on this workflow -------
echo "scenario: green checks merge while the auto-merge check is still running"
reset_state
run_script || { cat "$WORK/out.log" >&2; fail "green checks must merge the PR"; }
grep -q '^pr review --approve' "$STUB_LOG/gh.calls" || fail "the PR should be approved first"
grep -q "/commits/$OLD_SHA/check-runs" "$STUB_LOG/gh.calls" \
  || { cat "$WORK/out.log" >&2; fail "checks must be read without waiting on this workflow itself"; }
grep -q "^pr merge .*--match-head-commit $OLD_SHA.*--rebase --delete-branch" "$STUB_LOG/gh.calls" \
  || { cat "$WORK/out.log" >&2; fail "the tested head must be pinned when merging"; }
grep -q -- '--auto' "$STUB_LOG/gh.calls" && fail "auto-merge is unavailable without branch protection"
ok "green checks merged with the tested SHA pinned"

# --- scenario 2: a failing check blocks the merge -------------------------
echo "scenario: a failing check keeps the PR open"
reset_state
if run_script STUB_CHECKS=failing; then
  fail "a failing check must not be merged"
fi
grep -q '^pr merge' "$STUB_LOG/gh.calls" && fail "nothing may be merged while a check fails"
ok "failing check blocked the merge"

# --- scenario 3: no checks ever appear ------------------------------------
echo "scenario: a PR without checks does not hang forever"
reset_state
if run_script STUB_CHECKS=missing; then
  fail "a PR that never reports checks must not be merged"
fi
grep -q 'no checks appeared' "$WORK/out.log" \
  || { cat "$WORK/out.log" >&2; fail "the failure must say no checks appeared"; }
grep -q '^pr merge' "$STUB_LOG/gh.calls" && fail "nothing may be merged without checks"
ok "missing checks failed the run instead of merging blind"

# --- scenario 4: an approval refusal does not block the merge -------------
echo "scenario: an approval GitHub refuses does not stop the merge"
reset_state
run_script STUB_APPROVE=refused || { cat "$WORK/out.log" >&2; fail "a refused approval must not block the merge"; }
grep -q '^pr merge' "$STUB_LOG/gh.calls" || fail "the merge must still happen"
ok "refused approval tolerated"

# --- scenario 5: pending build checks are polled until they finish ---------
echo "scenario: pending build checks are polled instead of treated as missing"
reset_state
run_script STUB_CHECKS=pending || { cat "$WORK/out.log" >&2; fail "pending checks must be waited for"; }
[[ "$(cat "$STUB_LOG/polls")" -ge 2 ]] || fail "pending checks must be polled again"
grep -q '^pr merge' "$STUB_LOG/gh.calls" || fail "the PR must merge after the checks finish"
ok "pending checks were polled to completion"

# --- scenario 6: a new head after the checks is not merged untested --------
echo "scenario: a changed head is left for its own synchronize run"
reset_state
if run_script STUB_HEAD_CHANGED=1; then
  fail "a changed head must not merge the previously tested commit"
fi
grep -q '^pr merge' "$STUB_LOG/gh.calls" && fail "the untested head must not be merged"
grep -qi 'head' "$WORK/out.log" || { cat "$WORK/out.log" >&2; fail "the failure must explain the head change"; }
ok "changed head deferred to the new workflow run"

echo "PASS: dependabot PRs merge themselves once their checks are green"
