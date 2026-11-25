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
REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
SELF_CHECK_NAME="${AUTO_MERGE_CHECK_NAME:-Auto-merge Dependabot PRs}"
# A full build takes 10-15 minutes. Allow half an hour for runner queueing too.
CHECKS_WAIT_ATTEMPTS="${CHECKS_WAIT_ATTEMPTS:-90}"
POLL_SECONDS="${POLL_SECONDS:-20}"

if [[ -z "$PR_URL" ]]; then
  echo "::error::PR_URL not specified"
  exit 1
fi

head_sha="$(gh pr view "$PR_URL" --json headRefOid --jq .headRefOid)"
if [[ ! "$head_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::could not resolve the PR head commit" >&2
  exit 1
fi

# Approval is advisory: no rule requires it, and GitHub refuses some approvals
# (a token cannot approve every PR), which must not block the merge.
gh pr review --approve "$PR_URL" || true

# `gh pr checks` exits 8 while anything is pending, including this workflow's
# own check, so it can never report all-green here. Read the commit's check-run
# API instead: it returns pending states normally, and we exclude ourselves.
echo "=== Waiting for the checks on $PR_URL ($head_sha) ==="
count=0
pending=0
for attempt in $(seq 1 "$CHECKS_WAIT_ATTEMPTS"); do
  checks="$(gh api "repos/$REPO/commits/$head_sha/check-runs" --jq '.check_runs')"
  checks="$(jq --arg self "$SELF_CHECK_NAME" '[.[] | select(.name != $self)]' <<<"$checks")"
  count="$(jq 'length' <<<"$checks")"

  if (( count == 0 )); then
    sleep "$POLL_SECONDS"
    continue
  fi

  failed="$(jq '[.[] | select(.status == "completed" and
    .conclusion != "success" and .conclusion != "neutral" and
    .conclusion != "skipped" and .conclusion != null)] | length' <<<"$checks")"
  if (( failed > 0 )); then
    echo "::error::checks failed on $PR_URL; leaving it for a human" >&2
    jq -r '.[] | select(.status == "completed" and
      .conclusion != "success" and .conclusion != "neutral" and
      .conclusion != "skipped" and .conclusion != null) |
      "\(.name): \(.conclusion)"' <<<"$checks" >&2
    exit 1
  fi

  pending="$(jq '[.[] | select(.status != "completed" or .conclusion == null)] | length' <<<"$checks")"
  (( pending == 0 )) && break
  sleep "$POLL_SECONDS"
done

if (( count == 0 )); then
  echo "::error::no checks appeared on $PR_URL after ${CHECKS_WAIT_ATTEMPTS} attempt(s)" >&2
  exit 1
fi
if (( pending > 0 )); then
  echo "::error::checks on $PR_URL did not finish after ${CHECKS_WAIT_ATTEMPTS} attempt(s)" >&2
  exit 1
fi

# A synchronize push can land after the checks went green. GitHub rejects the
# merge if the head moved; its own run will then wait for the new checks.
current_sha="$(gh pr view "$PR_URL" --json headRefOid --jq .headRefOid)"
if [[ "$current_sha" != "$head_sha" ]]; then
  echo "::error::PR head changed from $head_sha to $current_sha; waiting for the new run" >&2
  exit 1
fi

echo "=== Merging $PR_URL at $head_sha ==="
gh pr merge "$PR_URL" --match-head-commit "$head_sha" --rebase --delete-branch

echo "✓ Dependabot PR merged and its branch deleted"
