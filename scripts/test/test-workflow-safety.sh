#!/usr/bin/env bash
#
# Structural contracts for failure reporting and Pages deployment. These are
# workflow-level decisions that cannot be exercised by the shell units alone.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUTO="$REPO_ROOT/.github/workflows/auto-update-and-release.yml"
BUILD="$REPO_ROOT/.github/workflows/build.yml"
RELEASE="$REPO_ROOT/.github/workflows/release.yml"
DEPENDABOT="$REPO_ROOT/.github/workflows/dependabot-auto-merge.yml"

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
report_block="$(awk '/^  report-outcome:/{printing=1} printing' "$AUTO")"
grep -q 'actions/checkout' <<<"$report_block" \
  && fail "reporting must not depend on a checkout"
grep -Fq 'scripts/actions/report-pipeline-outcome.sh?ref=$GITHUB_SHA' <<<"$report_block" \
  || fail "reporting must fetch the pinned reporter through the GitHub API"
grep -Fq 'bash -s --' <<<"$report_block" \
  || fail "reporting must execute the fetched reporter without a checkout"
grep -q '^        shell: bash$' <<<"$report_block" \
  || fail "reporting needs pipefail so a failed fetch cannot look successful"
grep -Fq 'GH_REPO: ${{ github.repository }}' <<<"$report_block" \
  || fail "reporting needs an explicit repository context without checkout"
grep -Fq '${{ needs.update-and-release.result }}' <<<"$report_block" \
  || fail "reporting must use the updater job result"
ok "failure reporting survives startup and checkout errors and leaves dry runs alone"

# --- scenario 3: every Pages publish step is gated on the current head ------
echo "scenario: stale builds cannot publish any Pages artifact"
grep -q '^      - name: Check Pages Commit Is Current$' "$BUILD" \
  || fail "the deploy job must check the current main head after queueing"
grep -Fq 'bash scripts/actions/check-pages-head.sh' "$BUILD" \
  || fail "the deploy job must use the failing current-head wrapper"
grep -Fq 'deploy=false' "$BUILD" && fail "a stale Pages deploy must fail, not succeed as a skip"
gates="$(grep -c "if: steps.current.outputs.deploy == 'true'" "$BUILD" || true)"
[[ "$gates" == 4 ]] || fail "all four Pages publishing steps must be gated (found $gates)"
ok "download, prepare, upload and deploy are gated on the current head"

# --- scenario 4: the merger can read the check-run API ----------------------
echo "scenario: the Dependabot merger has check-run read permission"
grep -q '^      checks: read$' "$DEPENDABOT" \
  || fail "the merger needs checks:read for the commit check-run API"
grep -q '^      actions: write$' "$DEPENDABOT" \
  || fail "the merger needs actions:write to rerun a transient failed build"
ok "Dependabot merger can read checks and rerun failed builds"

# --- scenario 5: publishing workflows require signed artifacts --------------
echo "scenario: main and release builds require signing"
grep -Fq "REQUIRE_SIGNING: \${{ github.event_name != 'pull_request' && '1' || '0' }}" "$BUILD" \
  || fail "main builds must require signing while pull requests may be unsigned"
grep -Fq "REQUIRE_SIGNING: '1'" "$AUTO" || fail "auto-update builds must require signing"
grep -Fq "REQUIRE_SIGNING: '1'" "$RELEASE" || fail "release builds must require signing"
ok "publishing workflows cannot silently produce unsigned repositories"

echo "PASS: workflow-level unattended safety contracts hold"
