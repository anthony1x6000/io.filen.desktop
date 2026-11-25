#!/usr/bin/env bash
set -euo pipefail

TAG="${GITHUB_REF#refs/tags/}"
BUNDLE_FILE="${1:-io.filen.desktop.flatpak}"

echo "=== Publishing GitHub Release $TAG ==="
if gh release view "$TAG" >/dev/null 2>&1; then
  # The scheduled auto-update already cut this tag's release, or a previous
  # attempt left it as a draft. Refresh the bundle and make sure it is public.
  echo "Release $TAG already exists; uploading the fresh bundle"
  gh release upload "$TAG" "$BUNDLE_FILE" --clobber
  gh release edit "$TAG" --draft=false --title "$TAG"
else
  gh release create "$TAG" "$BUNDLE_FILE" \
    --title "$TAG" \
    --generate-notes
fi

echo "✓ GitHub Release $TAG published successfully!"
