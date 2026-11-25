#!/usr/bin/env bash
set -euo pipefail

MANIFEST="io.filen.desktop.yaml"
METAINFO="io.filen.desktop.metainfo.xml"
BUNDLE="io.filen.desktop.flatpak"

# git and FEDC both refuse a repo they consider foreign; the workflow container
# needs this and it is a no-op once the workspace is already trusted.
git config --global --add safe.directory "$(pwd)" 2>/dev/null || true

echo "=== Installing flatpak-external-data-checker ==="
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y --user --noninteractive flathub org.flathub.flatpak-external-data-checker

echo "=== Checking for Upstream Updates ==="
# --edit-only keeps FEDC to editing files. Left to itself it commits with a
# sanitised git environment (no identity, foreign HOME) and exits 128, which
# took the whole daily run down before any release was cut.
flatpak run --env=GITHUB_TOKEN="${GITHUB_TOKEN:-}" --filesystem="$(pwd)" \
  org.flathub.flatpak-external-data-checker --update --edit-only "$MANIFEST"

VERSION="$(grep -oP 'releases/download/v\K[^/]+' "$MANIFEST" | head -n 1)"
TAG="v$VERSION"
NEW_VERSION=0

if [[ -n "$(git status --porcelain "$MANIFEST")" ]]; then
  echo "Found new version: $VERSION"
  NEW_VERSION=1
elif git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "No updates found."
  exit 0
else
  # A previous run committed the bump but died before tagging or releasing.
  # Without this the manifest looks current and the release never happens.
  echo "Manifest already at $VERSION but $TAG is unreleased; completing it"
fi

echo "=== Updating AppStream Metainfo ==="
python3 scripts/actions/update-metainfo.py "$VERSION"

echo "=== Building Flatpak Release ==="
bash scripts/build/build-flatpak.sh

git config user.name "Anthony"
git config user.email "33004321+anthony1x6000@users.noreply.github.com"

if [[ "$NEW_VERSION" == 1 ]]; then
  echo "=== Committing Version Bump ==="
  git add "$MANIFEST" "$METAINFO"
  git commit -m "chore(release): auto-update to $TAG"
  git push origin HEAD:main
fi

if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "=== Tagging $TAG ==="
  git tag "$TAG"
  git push origin "$TAG"
fi

if ! gh release view "$TAG" >/dev/null 2>&1; then
  echo "=== Publishing GitHub Release $TAG ==="
  gh release create "$TAG" "$BUNDLE" --title "$TAG" --generate-notes
fi

echo "✓ Successfully updated, built, and published release $TAG!"
