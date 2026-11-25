#!/usr/bin/env bash
#
# Merge a Dependabot PR once its checks are green.
#
# `gh pr merge --auto` is not usable here: GitHub only offers auto-merge on a
# branch whose protection requires checks, and main has no protection rules
# because the daily updater pushes to it directly. Asking for it fails with
# "Protected branch rules not configured for this branch". So the checks the PR
# triggers are waited for instead, and the merge happens in this job.
set -euo pipefail

PR_URL="${1:-${PR_URL:-}}"
CHECKS_WAIT_ATTEMPTS="${CHECKS_WAIT_ATTEMPTS:-60}"
POLL_SECONDS="${POLL_SECONDS:-10}"

if [[ -z "$PR_URL" ]]; then
  echo "::error::PR_URL not specified"
  exit 1
fi

# Approval is advisory: no rule requires it, and GitHub refuses some approvals
# (a token cannot approve every PR), which must not block the merge.
gh pr review --approve "$PR_URL" || true

echo "=== Waiting for the checks on $PR_URL ==="
count=0
for attempt in $(seq 1 "$CHECKS_WAIT_ATTEMPTS"); do
  count="$(gh pr checks "$PR_URL" --json name --jq 'length' 2>/dev/null || echo 0)"
  [[ "$count" =~ ^[0-9]+$ ]] && (( count > 0 )) && break
  sleep "$POLL_SECONDS"
done

if ! [[ "$count" =~ ^[0-9]+$ ]] || (( count == 0 )); then
  echo "::error::no checks appeared on $PR_URL after ${CHECKS_WAIT_ATTEMPTS} attempt(s)" >&2
  exit 1
fi

echo "=== Waiting for ${count} check(s) to finish ==="
if ! gh pr checks "$PR_URL" --watch --fail-fast --interval 30; then
  echo "::error::checks failed on $PR_URL; leaving it for a human" >&2
  exit 1
fi

echo "=== Merging $PR_URL ==="
gh pr merge "$PR_URL" --rebase --delete-branch

echo "✓ Dependabot PR merged and its branch deleted"
