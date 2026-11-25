#!/usr/bin/env bash
set -euo pipefail

MANIFEST="io.filen.desktop.yaml"
METAINFO="io.filen.desktop.metainfo.xml"
BUNDLE="io.filen.desktop.flatpak"
DRY_RUN="${AUTO_UPDATE_DRY_RUN:-0}"

tag_exists() { git rev-parse -q --verify "refs/tags/$1" >/dev/null; }
release_exists() { gh release view "$1" >/dev/null 2>&1; }

# git and FEDC both refuse a repo they consider foreign; the workflow container
# needs this and it is a no-op once the workspace is already trusted.
git config --global --add safe.directory "$(pwd)" 2>/dev/null || true

echo "=== Installing flatpak-external-data-checker ==="
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y --user --noninteractive flathub org.flathub.flatpak-external-data-checker

HEAD_BEFORE="$(git rev-parse HEAD)"

echo "=== Checking for Upstream Updates ==="
# --edit-only keeps FEDC to editing files. Left to itself it commits with a
# sanitised git environment (no identity, foreign HOME) and exits 128, which
# took the whole daily run down before any release was cut.
flatpak run --env=GITHUB_TOKEN="${GITHUB_TOKEN:-}" --filesystem="$(pwd)" \
  org.flathub.flatpak-external-data-checker --update --edit-only "$MANIFEST"

# Fail loudly if the checker ever commits on its own again instead of letting
# the run die later with a less obvious error.
if [[ "$(git rev-parse HEAD)" != "$HEAD_BEFORE" ]]; then
  echo "::error::the data checker committed the update itself; --edit-only is not in effect" >&2
  exit 1
fi

VERSION="$(grep -oP 'releases/download/v\K[^/]+' "$MANIFEST" | head -n 1)"
TAG="v$VERSION"
NEW_VERSION=0

if [[ -n "$(git status --porcelain "$MANIFEST")" ]]; then
  NEW_VERSION=1
fi

# A release is only finished once the bump, the tag and the GitHub release all
# exist. Checking all three lets a run that died part-way be completed instead
# of reporting "No updates found" forever.
if [[ "$NEW_VERSION" == 0 ]] && tag_exists "$TAG" && release_exists "$TAG"; then
  echo "No updates found."
  exit 0
fi

if [[ "$NEW_VERSION" == 1 ]]; then
  echo "Found new version: $VERSION"
elif ! tag_exists "$TAG"; then
  echo "Manifest already at $VERSION but $TAG is untagged; completing the release"
else
  echo "Manifest already at $VERSION but $TAG has no GitHub release; completing the release"
fi

echo "=== Updating AppStream Metainfo ==="
python3 scripts/actions/update-metainfo.py "$VERSION"

echo "=== Building Flatpak Release ==="
bash scripts/build/build-flatpak.sh

if [[ "$DRY_RUN" != 0 ]]; then
  echo "=== Dry run: update, build and release metadata verified; nothing published ==="
  exit 0
fi

git config user.name "Anthony"
git config user.email "33004321+anthony1x6000@users.noreply.github.com"

if [[ "$NEW_VERSION" == 1 ]]; then
  echo "=== Committing Version Bump ==="
  git add "$MANIFEST" "$METAINFO"
  git commit -m "chore(release): auto-update to $TAG"
  git push origin HEAD:main
fi

if ! tag_exists "$TAG"; then
  echo "=== Tagging $TAG ==="
  git tag "$TAG"
  git push origin "$TAG"
fi

if ! release_exists "$TAG"; then
  echo "=== Publishing GitHub Release $TAG ==="
  gh release create "$TAG" "$BUNDLE" --title "$TAG" --generate-notes
fi

# The commit and tag above are pushed with GITHUB_TOKEN, and pushes made with it
# start no workflows. Without this the Pages OSTree repository, which is what
# `flatpak update` actually pulls, would stay on the previous release.
echo "=== Triggering Build & Pages Deploy for $TAG ==="
if ! gh workflow run "Build & Validate Flatpak" --ref main; then
  echo "::error::could not dispatch the build/deploy workflow; Pages will lag behind $TAG" >&2
  exit 1
fi

echo "✓ Successfully updated, built, and published release $TAG!"
