#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
set -euo pipefail

PR_URL="${1:-${PR_URL:-}}"

if [[ -z "$PR_URL" ]]; then
  echo "::error::PR_URL not specified"
  exit 1
fi

echo "=== Approving and Merging Dependabot PR: $PR_URL ==="
gh pr review --approve "$PR_URL"
gh pr merge --auto --rebase "$PR_URL"

echo "✓ Dependabot PR approved and auto-merge enabled!"
