#!/usr/bin/env bash
# Mark the deploy job publishable only while this run still matches main. A
# stale run must fail: the auto-updater watches this job and would otherwise
# mistake a successful no-op for a completed Pages deployment.
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if bash "$SCRIPT_DIR/is-main-head.sh"; then
  echo "deploy=true" >> "$GITHUB_OUTPUT"
else
  status=$?
  if [[ "$status" == 1 ]]; then
    echo "::error::main advanced; refusing stale Pages deployment of $GITHUB_SHA" >&2
  else
    echo "::error::could not verify the Pages commit is current" >&2
  fi
  exit "$status"
fi
