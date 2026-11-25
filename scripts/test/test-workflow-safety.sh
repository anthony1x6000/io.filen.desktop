#!/usr/bin/env bash
#
# Structural contracts for failure reporting and Pages deployment. These are
# workflow-level decisions that cannot be exercised by the shell units alone.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUTO="$REPO_ROOT/.github/workflows/auto-update-and-release.yml"
BUILD="$REPO_ROOT/.github/workflows/build.yml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf '  ok: %s\n' "$*"; }

# --- scenario 1: only main can run the updater ------------------------------
echo "scenario: the updater is restricted to main"
grep -Fq "if: github.ref == 'refs/heads/main'" "$AUTO" \
  || fail "a manual dispatch from another branch must not run the updater"
ok "updater job restricted to main"

# --- scenario 2: reporting survives startup failure and skips dry runs -------
echo "scenario: reporting runs independently and ignores dry runs"
grep -q '^  report-outcome:' "$AUTO" || fail "reporting must be a separate job"
grep -q '^    needs: update-and-release$' "$AUTO" || fail "reporting must follow the updater job"
grep -Fq "if: always() && !inputs.dry_run && needs.update-and-release.result != 'skipped'" "$AUTO" \
  || fail "reporting must run after failures/cancellations but never for dry runs or skipped refs"
grep -Fq 'report-pipeline-outcome.sh "${{ needs.update-and-release.result }}"' "$AUTO" \
  || fail "reporting must use the updater job result"
ok "failure reporting survives startup errors and leaves dry runs alone"

# --- scenario 3: every Pages publish step is gated on the current head ------
echo "scenario: stale builds cannot publish any Pages artifact"
grep -q '^      - name: Check Pages Commit Is Current$' "$BUILD" \
  || fail "the deploy job must check the current main head after queueing"
gates="$(grep -c "if: steps.current.outputs.deploy == 'true'" "$BUILD" || true)"
[[ "$gates" == 4 ]] || fail "all four Pages publishing steps must be gated (found $gates)"
ok "download, prepare, upload and deploy are gated on the current head"

echo "PASS: workflow-level unattended safety contracts hold"
