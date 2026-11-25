#!/usr/bin/env bash
#
# Offline suite for scripts/actions/report-pipeline-outcome.sh.
#
# Nothing watches the Actions tab in an unattended repository, so a failing
# daily run has to leave a trace that persists in the repository itself: one
# issue that stays open while the pipeline fails and closes when it recovers.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_PARENT="$REPO_ROOT/.tmp"
mkdir -p "$TEST_PARENT"
WORK="$(mktemp -d "$TEST_PARENT/report-outcome.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

STUBS="$WORK/stubs"
export STUB_LOG="$WORK/log"
export STUB_ISSUES="$WORK/open-issue"
mkdir -p "$STUBS" "$STUB_LOG"
: > "$STUB_LOG/gh.calls"
: > "$STUB_LOG/actions"

export GITHUB_REPOSITORY="anthony1x6000/io.filen.desktop"
export GITHUB_SERVER_URL="https://github.com"
export GITHUB_RUN_ID="12345"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf '  ok: %s\n' "$*"; }

TITLE="Auto update & release pipeline is failing"

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
  "issue list")
    if [[ -s "$STUB_ISSUES" ]]; then
      emit '[{"number":'"$(cat "$STUB_ISSUES")"',"title":"Auto update & release pipeline is failing"}]' "$@"
    else
      emit '[]' "$@"
    fi
    ;;
  "issue create")
    printf 'create %s\n' "$*" >> "$STUB_LOG/actions"
    printf '101\n' > "$STUB_ISSUES"
    echo "https://github.com/anthony1x6000/io.filen.desktop/issues/101"
    ;;
  "issue comment")
    printf 'comment %s\n' "${3:-}" >> "$STUB_LOG/actions"
    ;;
  "issue close")
    printf 'close %s\n' "${3:-}" >> "$STUB_LOG/actions"
    : > "$STUB_ISSUES"
    ;;
esac
exit 0
STUB

chmod +x "$STUBS/gh"
export PATH="$STUBS:$PATH"

report() { # outcome
  bash "$REPO_ROOT/scripts/actions/report-pipeline-outcome.sh" "$1" > "$WORK/out.log" 2>&1
}

reset_state() { # $1 open issue number or "" -> fresh call log and issue state
  : > "$STUB_LOG/gh.calls"
  : > "$STUB_LOG/actions"
  : > "$STUB_ISSUES"
  [[ -n "${1:-}" ]] && printf '%s\n' "$1" > "$STUB_ISSUES"
  return 0
}

# --- scenario 1: first failure opens the issue ----------------------------
echo "scenario: the first failure opens an issue"
reset_state ""
report failure || { cat "$WORK/out.log" >&2; fail "reporting a failure must succeed"; }
grep -q '^create ' "$STUB_LOG/actions" || { cat "$WORK/out.log" >&2; fail "a failure must open an issue"; }
grep -qF -- "--title $TITLE" "$STUB_LOG/actions" || fail "the issue must use the known title"
grep -q 'actions/runs/12345' "$STUB_LOG/actions" || fail "the issue body must link the failing run"
ok "first failure opened an issue with the run link"

# --- scenario 2: further failures comment instead of spamming -------------
echo "scenario: further failures comment on the same issue"
reset_state 101
report failure || { cat "$WORK/out.log" >&2; fail "reporting another failure must succeed"; }
grep -q '^comment 101' "$STUB_LOG/actions" || fail "the open issue must be commented on"
grep -q '^create ' "$STUB_LOG/actions" && fail "a second issue must not be opened"
ok "repeat failure commented on the open issue"

# --- scenario 3: recovery closes the issue --------------------------------
echo "scenario: a green run closes the issue"
reset_state 101
report success || { cat "$WORK/out.log" >&2; fail "reporting a recovery must succeed"; }
grep -q '^close 101' "$STUB_LOG/actions" || fail "the open issue must be closed on recovery"
grep -q '^create ' "$STUB_LOG/actions" && fail "recovery must not open an issue"
ok "recovery closed the issue"

# --- scenario 4: a healthy run with nothing open mutates nothing ----------
echo "scenario: a green run with no open issue does nothing"
reset_state ""
report success || { cat "$WORK/out.log" >&2; fail "a healthy run must not fail the reporter"; }
[[ -s "$STUB_LOG/actions" ]] && { cat "$STUB_LOG/actions" >&2; fail "a healthy run must not touch issues"; }
ok "healthy run left the issue tracker alone"

# --- scenario 5: an unknown outcome is a bug, not a silent no-op ----------
echo "scenario: an unknown outcome fails loudly"
reset_state 101
if report exploded; then
  fail "an unknown outcome must not be accepted silently"
fi
ok "unknown outcome rejected"

# --- scenario 6: dry runs never touch the real failure issue ----------------
echo "scenario: a dry run cannot close or comment on a real failure"
reset_state 101
( export PIPELINE_DRY_RUN=1; report failure ) \
  || { cat "$WORK/out.log" >&2; fail "a dry-run report must be a no-op"; }
[[ -s "$STUB_LOG/gh.calls" ]] && { cat "$STUB_LOG/gh.calls" >&2; fail "dry run must not query or mutate issues"; }
[[ -s "$STUB_ISSUES" ]] || fail "dry run must leave the real failure issue open"
ok "dry run left the real issue tracker untouched"

# --- scenario 7: cancelled runs stay visible -------------------------------
echo "scenario: a cancelled run reports the interruption"
reset_state ""
report cancelled || { cat "$WORK/out.log" >&2; fail "reporting a cancellation must succeed"; }
grep -q '^create ' "$STUB_LOG/actions" || fail "a cancelled run must leave a visible issue"
ok "cancelled run opened the pipeline issue"

echo "PASS: pipeline failures stay visible in the repository until they recover"
