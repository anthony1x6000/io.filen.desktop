#!/usr/bin/env bash
set -euo pipefail

echo "=== Installing flatpak-external-data-checker ==="
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y --user --noninteractive flathub org.flathub.flatpak-external-data-checker

echo "=== Checking for Upstream Updates ==="
flatpak run --env=GITHUB_TOKEN="${GITHUB_TOKEN:-}" --filesystem="$(pwd)" org.flathub.flatpak-external-data-checker --update io.filen.desktop.yaml

if [[ -n "$(git status --porcelain io.filen.desktop.yaml)" ]]; then
  VERSION=$(grep -oP 'releases/download/v\K[^/]+' io.filen.desktop.yaml | head -n 1)
  echo "Found new version: $VERSION"

  echo "=== Updating AppStream Metainfo ==="
  python3 scripts/actions/update-metainfo.py "$VERSION"

  echo "=== Building Flatpak Release ==="
  bash scripts/build/build-flatpak.sh

  echo "=== Committing, Tagging, and Releasing ==="
  git config user.name "Anthony"
  git config user.email "33004321+anthony1x6000@users.noreply.github.com"

  git add io.filen.desktop.yaml io.filen.desktop.metainfo.xml
  git commit -m "chore(release): auto-update to v$VERSION" \
    -m "Co-authored-by: Antigravity Assistant <assistant@deepmind.google>"

  git push origin HEAD:main

  TAG="v$VERSION"
  git tag "$TAG"
  git push origin "$TAG"

  gh release create "$TAG" io.filen.desktop.flatpak \
    --title "$TAG" \
    --generate-notes

  echo "✓ Successfully updated, built, and published release $TAG!"
else
  echo "No updates found."
fi
