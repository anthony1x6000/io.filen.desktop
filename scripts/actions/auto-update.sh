#!/usr/bin/env bash
set -euo pipefail

MANIFEST="io.filen.desktop.yaml"
METAINFO="io.filen.desktop.metainfo.xml"
BUNDLE="io.filen.desktop.flatpak"
DRY_RUN="${AUTO_UPDATE_DRY_RUN:-0}"
UPSTREAM_REPO="FilenCloudDienste/filen-desktop"
CI_WORKFLOW="Build & Validate Flatpak"
CI_WORKFLOW_FILE="build.yml"

tag_exists() { git rev-parse -q --verify "refs/tags/$1" >/dev/null; }
release_exists() { gh release view "$1" >/dev/null 2>&1; }

# Latest upstream tag, without the leading v. Empty when GitHub cannot be
# reached, which is not fatal: the build below reports its own failures.
upstream_version() {
  gh api "repos/$UPSTREAM_REPO/releases/latest" --jq '.tag_name' 2>/dev/null \
    | sed 's/^v//' || true
}

# Push a change with GITHUB_TOKEN starts no workflows, so Pages only learns
# about a release through this dispatch. The release is not shipped until that
# run is green, so follow it instead of firing and forgetting: a red run is
# otherwise invisible in an unattended repository.
dispatch_and_watch_ci() {
  local before="" run_id="" attempt
  before="$(gh run list --workflow "$CI_WORKFLOW_FILE" --event workflow_dispatch --limit 1 \
    --json databaseId --jq '.[0].databaseId // 0' 2>/dev/null || echo 0)"

  if ! gh workflow run "$CI_WORKFLOW" --ref main; then
    echo "::error::could not dispatch the build/deploy workflow; Pages will lag behind $TAG" >&2
    return 1
  fi

  for attempt in $(seq 1 "${CI_WAIT_ATTEMPTS:-24}"); do
    run_id="$(gh run list --workflow "$CI_WORKFLOW_FILE" --event workflow_dispatch --limit 5 \
      --json databaseId --jq "[.[] | select(.databaseId > $before)][0].databaseId // empty" \
      2>/dev/null || true)"
    [[ -n "$run_id" ]] && break
    sleep "${POLL_SECONDS:-5}"
  done

  if [[ -z "$run_id" ]]; then
    echo "::error::the build/deploy workflow was dispatched but no run appeared" >&2
    return 1
  fi

  echo "=== Watching build & Pages deploy run $run_id ==="
  if ! gh run watch "$run_id" --exit-status --interval 20; then
    echo "::error::build/deploy run $run_id failed; GitHub Pages is not serving $TAG" >&2
    return 1
  fi
}

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
  # The data checker is the only thing that notices a newer release upstream.
  # One that quietly stopped noticing would leave this run reporting "No
  # updates found" while the Flatpak falls behind, which is how it drifted
  # before, so compare against upstream directly instead of trusting it.
  UPSTREAM="$(upstream_version)"
  if [[ -n "$UPSTREAM" && "$UPSTREAM" != "$VERSION" ]]; then
    echo "::error::upstream is at v$UPSTREAM but the manifest pins v$VERSION; the data checker did not pick the release up" >&2
    exit 1
  fi

  echo "No updates found; re-verifying the build and Pages deploy"
  dispatch_and_watch_ci || exit 1
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

# The Pages OSTree repository is what `flatpak update` actually pulls, so the
# release is only finished once the build/deploy run for it is green.
echo "=== Building and deploying $TAG through CI ==="
if ! dispatch_and_watch_ci; then
  echo "::error::release $TAG is published but Pages was not updated" >&2
  exit 1
fi

echo "✓ Successfully updated, built, and published release $TAG!"
