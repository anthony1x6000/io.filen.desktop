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
GH_RETRY_ATTEMPTS="${GH_RETRY_ATTEMPTS:-5}"
GH_RETRY_SECONDS="${GH_RETRY_SECONDS:-5}"

retry_gh() {
  local attempt delay="$GH_RETRY_SECONDS"
  for attempt in $(seq 1 "$GH_RETRY_ATTEMPTS"); do
    if "$@"; then
      return 0
    fi
    if (( attempt < GH_RETRY_ATTEMPTS )); then
      sleep "$delay"
      delay=$((delay * 2))
    fi
  done
  return 1
}

if [[ -z "$PR_URL" ]]; then
  echo "::error::PR_URL not specified"
  exit 1
fi

RERUN_LOG="$(mktemp)"
trap 'rm -f "$RERUN_LOG"' EXIT

head_sha="$(retry_gh gh pr view "$PR_URL" --json headRefOid --jq .headRefOid)" || {
  echo "::error::could not resolve the PR head commit" >&2
  exit 1
}
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
green=0
for attempt in $(seq 1 "$CHECKS_WAIT_ATTEMPTS"); do
  if ! checks="$(retry_gh gh api "repos/$REPO/commits/$head_sha/check-runs" --jq '.check_runs')"; then
    echo "::error::could not read the checks on $PR_URL after ${GH_RETRY_ATTEMPTS} attempt(s)" >&2
    exit 1
  fi
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
    jq -r '.[] | select(.status == "completed" and
      .conclusion != "success" and .conclusion != "neutral" and
      .conclusion != "skipped" and .conclusion != null) |
      "\(.name): \(.conclusion)"' <<<"$checks" >&2

    # Runner/network failures are transient. Give each failed workflow run one
    # rerun and watch it; a deterministic dependency breakage fails again and
    # remains terminal instead of looping forever.
    run_ids="$(jq -r '[.[] | select(.status == "completed" and
      .conclusion != "success" and .conclusion != "neutral" and
      .conclusion != "skipped" and .conclusion != null) |
      (.details_url // "" | try (capture("/actions/runs/(?<id>[0-9]+)").id) catch empty)] |
      unique[]' <<<"$checks")"
    if [[ -z "$run_ids" ]]; then
      echo "::error::checks failed on $PR_URL and cannot be rerun automatically" >&2
      exit 1
    fi

    reran=0
    while IFS= read -r run_id; do
      [[ -n "$run_id" ]] || continue
      grep -qx "$run_id" "$RERUN_LOG" && continue
      echo "=== Rerunning failed workflow run $run_id once ==="
      retry_gh gh run rerun "$run_id" --failed || {
        echo "::error::could not rerun workflow run $run_id" >&2
        exit 1
      }
      printf '%s\n' "$run_id" >> "$RERUN_LOG"
      retry_gh gh run watch "$run_id" --exit-status --interval 20 || {
        echo "::error::rerun of $run_id failed; leaving $PR_URL for a human" >&2
        exit 1
      }
      reran=1
    done <<<"$run_ids"

    if (( reran == 0 )); then
      echo "::error::checks still fail on $PR_URL after their one rerun" >&2
      exit 1
    fi
    sleep "$POLL_SECONDS"
    continue
  fi

  pending="$(jq '[.[] | select(.status != "completed" or .conclusion == null)] | length' <<<"$checks")"
  if (( pending == 0 )); then
    green=1
    break
  fi
  sleep "$POLL_SECONDS"
done

if (( count == 0 )); then
  echo "::error::no checks appeared on $PR_URL after ${CHECKS_WAIT_ATTEMPTS} attempt(s)" >&2
  exit 1
fi
if (( green == 0 )); then
  echo "::error::checks on $PR_URL did not finish successfully after ${CHECKS_WAIT_ATTEMPTS} attempt(s)" >&2
  exit 1
fi

# A synchronize push can land after the checks went green. GitHub rejects the
# merge if the head moved; its own run will then wait for the new checks.
current_sha="$(retry_gh gh pr view "$PR_URL" --json headRefOid --jq .headRefOid)" || {
  echo "::error::could not re-check the PR head before merging" >&2
  exit 1
}
if [[ "$current_sha" != "$head_sha" ]]; then
  echo "::error::PR head changed from $head_sha to $current_sha; waiting for the new run" >&2
  exit 1
fi

echo "=== Merging $PR_URL at $head_sha ==="
gh pr merge "$PR_URL" --match-head-commit "$head_sha" --rebase --delete-branch

echo "✓ Dependabot PR merged and its branch deleted"
