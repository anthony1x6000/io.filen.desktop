#!/usr/bin/env bash
#
# Keep one issue open in the repository while the daily pipeline is failing.
#
# An unattended repository has nobody watching the Actions tab, so a failure
# has to leave a trace that survives in the repo: the first failing run opens
# the issue, later failures comment on it, and the first run that succeeds
# closes it again.
#
# Usage: report-pipeline-outcome.sh <success|failure|cancelled>
set -euo pipefail

OUTCOME="${1:?outcome (success, failure or cancelled) is required}"
TITLE="Auto update & release pipeline is failing"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}/actions/runs/${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"

open_issue() {
  gh issue list --state open --limit 100 --json number,title \
    --jq "[.[] | select(.title == \"$TITLE\")][0].number // empty"
}

issue="$(open_issue)"

case "$OUTCOME" in
  success)
    if [[ -n "$issue" ]]; then
      gh issue close "$issue" --comment "Recovered: ${RUN_URL} succeeded."
    else
      echo "Pipeline healthy; no failure issue is open."
    fi
    ;;
  failure|cancelled)
    if [[ -n "$issue" ]]; then
      gh issue comment "$issue" --body "Still failing: ${RUN_URL}"
    else
      gh issue create --title "$TITLE" \
        --body "The daily auto-update run failed: ${RUN_URL}

It stays open until a run succeeds."
    fi
    ;;
  *)
    echo "::error::unknown outcome '$OUTCOME'" >&2
    exit 1
    ;;
esac
