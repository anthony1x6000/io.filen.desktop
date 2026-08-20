#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
set -euo pipefail

TAG="${GITHUB_REF#refs/tags/}"
BUNDLE_FILE="${1:-io.filen.desktop.flatpak}"

echo "=== Publishing GitHub Release $TAG ==="
gh release create "$TAG" "$BUNDLE_FILE" \
  --title "$TAG" \
  --generate-notes

echo "✓ GitHub Release $TAG published successfully!"
