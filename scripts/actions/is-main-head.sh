#!/usr/bin/env bash
# Exit 0 when this run still matches main, 1 when it is stale, and 2 when the
# remote head cannot be determined. The deploy job uses those distinct states
# to skip an older queued build without hiding an API/network failure.
set -euo pipefail

: "${GITHUB_SHA:?GITHUB_SHA is required}"

if ! remote_head="$(git ls-remote origin refs/heads/main 2>/dev/null | awk 'NR == 1 {print $1}')" \
    || [[ -z "$remote_head" ]]; then
  echo "::error::could not determine the current main head" >&2
  exit 2
fi

[[ "$remote_head" == "$GITHUB_SHA" ]]
