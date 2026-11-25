#!/usr/bin/env bash
#
# Offline regression suite for the release pipeline
# (scripts/actions/auto-update.sh and scripts/build/publish-release.sh).
#
# The daily workflow broke because flatpak-external-data-checker (FEDC) commits
# its edits by itself after --update, and its sanitised git environment cannot
# commit inside the container ("Author identity unknown" -> exit 128). That
# killed the run before the release was ever cut, leaving the Flatpak months
# behind upstream.
#
# flatpak, gh and the flatpak build are stubbed here, so the suite needs no
# network and no flatpak runtime. The FEDC stub reproduces that same commit
# failure whenever it is not told --edit-only, and the release history is
# rewound so consecutive upstream releases are replayed the way they arrive.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_PARENT="$REPO_ROOT/.tmp"
mkdir -p "$TEST_PARENT"
WORK="$(mktemp -d "$TEST_PARENT/auto-update.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Keep every `git config --global` write inside the sandbox and start with no
# identity anywhere, exactly like the workflow container.
export GIT_CONFIG_GLOBAL="$WORK/global.gitconfig"
: > "$GIT_CONFIG_GLOBAL"
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

export GITHUB_TOKEN=dummy-token
export GH_TOKEN=dummy-token

STUBS="$WORK/stubs"
export STUB_LOG="$WORK/log"
export STUB_RELEASES="$WORK/releases"
export STUB_FEDC_HOME="$WORK/fedc-home"
mkdir -p "$STUBS" "$STUB_LOG" "$STUB_RELEASES" "$STUB_FEDC_HOME"
: > "$STUB_LOG/fedc.calls"
: > "$STUB_LOG/gh.calls"
: > "$STUB_LOG/build.calls"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf '  ok: %s\n' "$*"; }

assert_eq() { # expected actual message
  [[ "$1" == "$2" ]] || fail "$3 (expected '$1', got '$2')"
  ok "$3"
}

# --- flatpak stub: emulates FEDC, including its broken commit path -----------
cat > "$STUBS/flatpak" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
# remote-add / install are not interesting
[[ "${1:-}" == "run" ]] || exit 0
shift

manifest=""
edit_only=0
for arg in "$@"; do
  case "$arg" in
    --edit-only) edit_only=1 ;;
    --update|org.flathub.flatpak-external-data-checker|--env=*|--filesystem=*) ;;
    -*) ;;
    *) manifest="$arg" ;;
  esac
done
printf '%s\n' "$*" >> "$STUB_LOG/fedc.calls"

[[ -n "$manifest" && -f "$manifest" ]] || { echo "stub FEDC: manifest not found" >&2; exit 2; }

current="$(grep -oP 'releases/download/v\K[^/]+' "$manifest" | head -n 1)"
[[ "$current" == "$STUB_LATEST_VERSION" ]] && exit 0

python3 - "$manifest" "$STUB_LATEST_VERSION" <<'PY'
import pathlib, re, sys
path, latest = pathlib.Path(sys.argv[1]), sys.argv[2]
text = path.read_text()
text = re.sub(r'releases/download/v[^/]+/', f'releases/download/v{latest}/', text)
text = re.sub(r'(sha256: )[0-9a-f]{64}', r'\g<1>' + 'f' * 64, text)
path.write_text(text)
PY

# A checker that commits by itself, which is what the container does without
# --edit-only. With a sanitised HOME it has no identity and dies, exactly like
# the failing workflow runs. STUB_FEDC_COMMITS=1 additionally ignores
# --edit-only, to prove the script's own guard catches a future regression.
if [[ "${STUB_FEDC_COMMITS:-0}" == 1 ]]; then
  env -i PATH="/usr/bin:/bin" HOME="$STUB_FEDC_HOME" \
    git -c user.name=checker -c user.email=checker@example.com \
    commit --no-verify --no-gpg-sign -am "filen: Update to $STUB_LATEST_VERSION"
elif [[ "$edit_only" != 1 ]]; then
  env -i PATH="/usr/bin:/bin" HOME="$STUB_FEDC_HOME" \
    git commit --no-verify --no-gpg-sign -am "filen: Update to $STUB_LATEST_VERSION"
fi
exit 0
STUB

# --- gh stub: records releases, CI dispatch and upstream lookups -----------
cat > "$STUBS/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$STUB_LOG/gh.calls"

emit() { # $1 json -> applies the --jq expression the caller asked for
  local expr="" prev="" arg
  for arg in "$@"; do
    [[ "$prev" == "--jq" ]] && expr="$arg"
    prev="$arg"
  done
  if [[ -n "$expr" ]]; then
    printf '%s' "$1" | jq -r "$expr"
  else
    printf '%s\n' "$1"
  fi
}

run_id() { cat "$STUB_LOG/last-run-id" 2>/dev/null || echo 1000; }

case "${1:-} ${2:-}" in
  "release view")
    [[ -f "$STUB_RELEASES/${3:-}" ]] || exit 1
    case "$(cat "$STUB_RELEASES/${3:-}")" in
      draft) printf '%s\n' '{"isDraft":true,"assets":[]}' ;;
      missing-asset) printf '%s\n' '{"isDraft":false,"assets":[]}' ;;
      *) printf '%s\n' '{"isDraft":false,"assets":[{"name":"io.filen.desktop.flatpak"}]}' ;;
    esac
    ;;
  "release create"|"release upload")
    printf '%s\n' "${STUB_RELEASE_CREATE_STATE:-complete}" > "$STUB_RELEASES/${3:-}"
    ;;
  "release edit")
    state="$(cat "$STUB_RELEASES/${3:-}")"
    for arg in "$@"; do
      [[ "$arg" == "--draft=false" ]] && state=complete
      [[ "$arg" == "--draft=true" ]] && state=draft
    done
    printf '%s\n' "$state" > "$STUB_RELEASES/${3:-}"
    ;;
  "workflow run")
    printf '%s\n' "$(( $(run_id) + 1 ))" > "$STUB_LOG/last-run-id"
    ;;
  "run list")
    emit '[{"databaseId":'"$(run_id)"',"headSha":"'"$(git rev-parse HEAD)"'"}]' "$@"
    ;;
  "run watch")
    [[ "${STUB_CI_CONCLUSION:-success}" == "success" ]] || exit 1
    ;;
  "api "*)
    case "$2" in
      *releases/latest) [[ -n "${STUB_UPSTREAM_TAG:-}" ]] && printf 'v%s\n' "$STUB_UPSTREAM_TAG" ;;
    esac
    ;;
esac
exit 0
STUB

chmod +x "$STUBS/flatpak" "$STUBS/gh"
export PATH="$STUBS:$PATH"

new_workspace() { # $1 name -> prints workspace path, seeds a bare remote at HEAD's manifest
  local root="$WORK/$1"
  mkdir -p "$root"
  git init -q --bare -b main "$root/remote.git"
  git clone -q "$root/remote.git" "$root/ws"
  cp -a "$REPO_ROOT/io.filen.desktop.yaml" \
        "$REPO_ROOT/io.filen.desktop.metainfo.xml" \
        "$REPO_ROOT/scripts" "$root/ws/"
  cat > "$root/ws/scripts/build/build-flatpak.sh" <<'BUILD'
#!/usr/bin/env bash
set -euo pipefail
echo "bespoke build" >> "$STUB_LOG/build.calls"
: > io.filen.desktop.flatpak
BUILD
  git -C "$root/ws" -c user.name=seed -c user.email=seed@example.com add -A
  git -C "$root/ws" -c user.name=seed -c user.email=seed@example.com \
    commit -q -m "seed"
  git -C "$root/ws" push -q origin main
  printf '%s\n' "$root"
}

rewind_manifest() { # ws version -> pretend the repo was left at an older release
  python3 - "$1/io.filen.desktop.yaml" "$2" <<'PY'
import pathlib, re, sys
path, version = pathlib.Path(sys.argv[1]), sys.argv[2]
text = path.read_text()
path.write_text(re.sub(r'releases/download/v[^/]+/', f'releases/download/v{version}/', text))
PY
  git -C "$1" add io.filen.desktop.yaml
  git -C "$1" -c user.name=seed -c user.email=seed@example.com \
    commit -q -m "chore: rewind to $2"
}

run_update() { # ws -> runs the real script, logs to $WORK/last.log
  if ( cd "$1" && bash scripts/actions/auto-update.sh ) > "$WORK/last.log" 2>&1; then
    return 0
  fi
  echo "--- auto-update.sh output ---" >&2
  cat "$WORK/last.log" >&2
  return 1
}

run_dry_update() { # ws -> runs the real script with publishing suppressed
  if ( cd "$1" && AUTO_UPDATE_DRY_RUN=1 bash scripts/actions/auto-update.sh ) > "$WORK/last.log" 2>&1; then
    return 0
  fi
  echo "--- auto-update.sh output ---" >&2
  cat "$WORK/last.log" >&2
  return 1
}

run_publish() { # ws tag -> runs the tag-triggered release script
  if ( cd "$1" && GITHUB_REF="refs/tags/$2" bash scripts/build/publish-release.sh io.filen.desktop.flatpak ) \
      > "$WORK/last.log" 2>&1; then
    return 0
  fi
  echo "--- publish-release.sh output ---" >&2
  cat "$WORK/last.log" >&2
  return 1
}

manifest_version() { grep -oP 'releases/download/v\K[^/]+' "$1/io.filen.desktop.yaml" | head -n 1; }
remote_tag_list() { git --git-dir="$1/remote.git" tag --list; }
remote_commits() { git --git-dir="$1/remote.git" rev-list --count main; }
released() { [[ -f "$STUB_RELEASES/$1" ]]; }

# --- scenario 1: upstream shipped a new version ----------------------------
echo "scenario: new upstream release is packaged, tagged and published"
export STUB_LATEST_VERSION=9.9.9
root="$(new_workspace new-release-main)"
run_update "$root/ws" || fail "auto-update.sh must succeed without FEDC's own commit"

assert_eq "9.9.9" "$(manifest_version "$root/ws")" \
  "manifest bumped to the new upstream version"
assert_eq "2" "$(remote_commits "$root")" "exactly one release commit was pushed"
assert_eq "33004321+anthony1x6000@users.noreply.github.com" \
  "$(git --git-dir="$root/remote.git" log -1 --format=%ae main)" \
  "release commit uses the repository identity"
assert_eq "v9.9.9" "$(remote_tag_list "$root")" "release tag pushed"
released v9.9.9 || fail "release v9.9.9 was never published"
ok "release v9.9.9 published with the bundle"
grep -q 'version="9.9.9"' "$root/ws/io.filen.desktop.metainfo.xml" \
  || fail "metainfo.xml has no 9.9.9 release entry"
ok "metainfo.xml documents the new release"
grep -q -- '--edit-only' "$STUB_LOG/fedc.calls" \
  || fail "FEDC must run with --edit-only, otherwise it commits on its own"
ok "FEDC runs in --edit-only mode"
grep -q 'workflow run Build & Validate Flatpak --ref main' "$STUB_LOG/gh.calls" \
  || fail "the build/deploy workflow must be dispatched, or Pages never picks the release up"
ok "build & Pages deploy dispatched for the released commit"
grep -q 'run watch' "$STUB_LOG/gh.calls" \
  || fail "the dispatched run must be watched, or a failed Pages deploy stays invisible"
ok "dispatched build & Pages deploy watched to completion"

# --- scenario 2: nothing new upstream --------------------------------------
echo "scenario: no upstream release leaves the repo untouched and re-checks the deploy"
export STUB_LATEST_VERSION="$(manifest_version "$root/ws")"
export STUB_UPSTREAM_TAG="$STUB_LATEST_VERSION"
before_commits="$(remote_commits "$root")"
: > "$STUB_LOG/gh.calls"
: > "$STUB_LOG/build.calls"
run_update "$root/ws" || fail "auto-update.sh must exit cleanly when nothing changed"
assert_eq "$before_commits" "$(remote_commits "$root")" "no extra commit on rerun"
assert_eq "" "$(cat "$STUB_LOG/build.calls")" "no wasted local flatpak build"
grep -q 'release create' "$STUB_LOG/gh.calls" && fail "no release must be created"
ok "no release published"
grep -q 'No updates found' "$WORK/last.log" || fail "a steady-state run must report no update"
grep -q 'run watch' "$STUB_LOG/gh.calls" \
  || fail "a steady-state run must still verify the build and Pages deploy"
ok "steady state still verifies the build & Pages deploy"

# --- scenario 3: bump landed but tagging/releasing died --------------------
echo "scenario: run that died before tagging is completed on the next run"
git --git-dir="$root/remote.git" tag -d v9.9.9 > /dev/null
git -C "$root/ws" tag -d v9.9.9 > /dev/null
rm -f "$STUB_RELEASES/v9.9.9"
: > "$STUB_LOG/build.calls"
run_update "$root/ws" || fail "auto-update.sh must complete an interrupted release"
assert_eq "$before_commits" "$(remote_commits "$root")" "no duplicate release commit"
assert_eq "v9.9.9" "$(remote_tag_list "$root")" "missing tag recreated"
released v9.9.9 || fail "missing release was never published"
ok "release recreated from the already-bumped manifest"

# --- scenario 4: tagged, but the GitHub release never got created ----------
echo "scenario: run that died before publishing is completed on the next run"
rm -f "$STUB_RELEASES/v9.9.9"
: > "$STUB_LOG/gh.calls"
run_update "$root/ws" || fail "auto-update.sh must publish a tagged but unreleased version"
assert_eq "$before_commits" "$(remote_commits "$root")" "no duplicate commit"
assert_eq "v9.9.9" "$(remote_tag_list "$root")" "tag left untouched"
released v9.9.9 || fail "missing release was never published"
ok "missing GitHub release published for the existing tag"

# --- scenario 5: dry run exercises everything, publishes nothing -----------
echo "scenario: dry run verifies the pipeline without side effects"
dry_root="$(new_workspace dry-run)"
export STUB_LATEST_VERSION=8.8.8
dry_head="$(git -C "$dry_root/ws" rev-parse HEAD)"
run_dry_update "$dry_root/ws" || fail "dry run must succeed"
assert_eq "8.8.8" "$(manifest_version "$dry_root/ws")" "dry run detects the new version"
assert_eq "$dry_head" "$(git -C "$dry_root/ws" rev-parse HEAD)" "dry run creates no commit"
assert_eq "1" "$(remote_commits "$dry_root")" "dry run pushes nothing"
assert_eq "" "$(remote_tag_list "$dry_root")" "dry run tags nothing"
released 8.8.8 && fail "dry run must not publish a release"
ok "dry run published nothing"
[[ -s "$STUB_LOG/build.calls" ]] || fail "dry run must still exercise the real build"
ok "dry run still exercises the build"

# --- scenario 6: tag push fires release.yml after the auto-updater released -
echo "scenario: release.yml tolerates a release the auto-updater already cut"
: > "$STUB_LOG/gh.calls"
: > "$STUB_RELEASES/v9.9.9"
run_publish "$root/ws" v9.9.9 || fail "publish-release.sh must not fail on an existing release"
grep -q 'release create' "$STUB_LOG/gh.calls" && fail "existing release must not be created twice"
grep -q 'release upload v9.9.9' "$STUB_LOG/gh.calls" || fail "existing release must get the fresh bundle"
ok "existing release refreshed rather than duplicated"

# --- scenario 7: tag push with no release yet ------------------------------
echo "scenario: release.yml publishes when no release exists"
: > "$STUB_LOG/gh.calls"
rm -f "$STUB_RELEASES/v9.9.9"
run_publish "$root/ws" v9.9.9 || fail "publish-release.sh must create a missing release"
grep -q 'release create v9.9.9' "$STUB_LOG/gh.calls" || fail "missing release must be published"
ok "missing release published"

# --- scenario 8: a checker that commits anyway is caught -------------------
echo "scenario: a checker that commits on its own fails the run loudly"
guard_root="$(new_workspace guard)"
export STUB_LATEST_VERSION=7.7.7
if ( cd "$guard_root/ws" && STUB_FEDC_COMMITS=1 bash scripts/actions/auto-update.sh ) \
    > "$WORK/last.log" 2>&1; then
  fail "a self-committing checker must fail the run"
fi
grep -q 'committed the update itself' "$WORK/last.log" \
  || fail "the guard must explain that the checker committed on its own"
ok "self-committing checker rejected with a clear error"

# --- scenario 9: rewind history and replay the releases as they arrived ----
echo "scenario: repo rewound to 3.0.51, then upstream releases 3.0.52..3.0.55 arrive"
replay_root="$(new_workspace replay)"
rewind_manifest "$replay_root/ws" 3.0.51
git -C "$replay_root/ws" push -q origin main
assert_eq "3.0.51" "$(manifest_version "$replay_root/ws")" "repo rewound to 3.0.51"

replay_commits=2 # seed + rewind
for version in 3.0.52 3.0.53 3.0.54 3.0.55; do
  export STUB_LATEST_VERSION="$version"
  run_update "$replay_root/ws" || fail "releasing $version failed"
  replay_commits=$((replay_commits + 1))
  assert_eq "$version" "$(manifest_version "$replay_root/ws")" "shipped $version"
  assert_eq "v$version" "$(git --git-dir="$replay_root/remote.git" tag --list "v$version")" "tagged $version"
  released "v$version" || fail "release v$version missing"
  grep -q "version=\"$version\"" "$replay_root/ws/io.filen.desktop.metainfo.xml" \
    || fail "metainfo.xml missing $version"
done

assert_eq "$replay_commits" "$(remote_commits "$replay_root")" "one commit per release, no duplicates"
assert_eq "v3.0.52 v3.0.53 v3.0.54 v3.0.55" "$(remote_tag_list "$replay_root" | sort -V | tr '\n' ' ' | sed 's/ $//')" \
  "every replayed version has exactly one tag"

# --- scenario 10: the dispatched build/deploy fails -----------------------
echo "scenario: a dispatched build that fails fails the daily run"
ci_root="$(new_workspace ci-failure)"
export STUB_LATEST_VERSION=6.6.6
unset STUB_UPSTREAM_TAG
: > "$STUB_LOG/gh.calls"
if ( cd "$ci_root/ws" && STUB_CI_CONCLUSION=failure bash scripts/actions/auto-update.sh ) \
    > "$WORK/last.log" 2>&1; then
  fail "a failed build/deploy run must fail the daily run"
fi
grep -q 'Pages is not serving' "$WORK/last.log" \
  || fail "the failure must say that Pages is behind the release"
ok "failed build/deploy fails the daily run"

# --- scenario 11: the data checker silently stops seeing releases ---------
echo "scenario: upstream is ahead of the manifest but the checker saw nothing"
drift_root="$(new_workspace drift)"
drift_version="$(manifest_version "$drift_root/ws")"
git -C "$drift_root/ws" tag "v$drift_version"
git -C "$drift_root/ws" push -q origin "v$drift_version"
: > "$STUB_RELEASES/v$drift_version"
export STUB_LATEST_VERSION="$drift_version"
export STUB_UPSTREAM_TAG=9.9.9
: > "$STUB_LOG/gh.calls"
if ( cd "$drift_root/ws" && bash scripts/actions/auto-update.sh ) > "$WORK/last.log" 2>&1; then
  fail "a checker that stopped seeing releases must fail the run"
fi
grep -q 'did not pick the release up' "$WORK/last.log" \
  || fail "the drift guard must say the checker missed the release"
grep -q 'workflow run' "$STUB_LOG/gh.calls" && fail "a drifted run must not deploy anything"
ok "silent upstream drift fails the run instead of reporting no update"

# --- scenario 12: a scheduled run keeps its own schedule enabled -------------
echo "scenario: a scheduled run keeps its own workflow enabled"
keepalive="$(new_workspace keepalive)"
keepalive_version="$(manifest_version "$keepalive/ws")"
git -C "$keepalive/ws" tag "v$keepalive_version"
git -C "$keepalive/ws" push -q origin "v$keepalive_version"
: > "$STUB_RELEASES/v$keepalive_version"
export STUB_LATEST_VERSION="$keepalive_version"
export STUB_UPSTREAM_TAG="$keepalive_version"
: > "$STUB_LOG/gh.calls"
if ( cd "$keepalive/ws" && GITHUB_EVENT_NAME=schedule GITHUB_REPOSITORY=example/repo \
    bash scripts/actions/auto-update.sh ) > "$WORK/last.log" 2>&1; then
  :
else
  fail "a scheduled run must keep the workflow enabled and verify the deploy"
fi
assert_eq "1" "$(remote_commits "$keepalive")" "keeping the schedule alive needs no dummy commit"
grep -q 'api -X PUT repos/example/repo/actions/workflows/auto-update-and-release.yml/enable' \
  "$STUB_LOG/gh.calls" || fail "the scheduled run must re-enable its own workflow"
ok "scheduled workflow is re-enabled before GitHub can disable it"
grep -q 'run watch' "$STUB_LOG/gh.calls" \
  || fail "the build after a keepalive must still be watched"
ok "scheduled run still verifies the build & Pages deploy"

# --- scenario 13: dry run on a quiet day publishes nothing -------------------
echo "scenario: a steady-state dry run does not dispatch a real deployment"
dry_steady="$(new_workspace dry-steady)"
dry_steady_version="$(manifest_version "$dry_steady/ws")"
git -C "$dry_steady/ws" tag "v$dry_steady_version"
git -C "$dry_steady/ws" push -q origin "v$dry_steady_version"
: > "$STUB_RELEASES/v$dry_steady_version"
export STUB_LATEST_VERSION="$dry_steady_version"
export STUB_UPSTREAM_TAG="$dry_steady_version"
: > "$STUB_LOG/gh.calls"
dry_steady_head="$(git -C "$dry_steady/ws" rev-parse HEAD)"
run_dry_update "$dry_steady/ws" || fail "steady-state dry run must succeed"
assert_eq "$dry_steady_head" "$(git -C "$dry_steady/ws" rev-parse HEAD)" \
  "steady-state dry run creates no commit"
assert_eq "1" "$(remote_commits "$dry_steady")" "steady-state dry run pushes nothing"
grep -q 'workflow run' "$STUB_LOG/gh.calls" && fail "steady-state dry run must not deploy to Pages"
ok "steady-state dry run has no publishing side effects"

# --- scenario 14: a release whose asset upload failed is repaired -----------
echo "scenario: an existing release with no bundle is repaired"
partial="$(new_workspace partial-release)"
partial_version="$(manifest_version "$partial/ws")"
git -C "$partial/ws" tag "v$partial_version"
git -C "$partial/ws" push -q origin "v$partial_version"
printf '%s\n' missing-asset > "$STUB_RELEASES/v$partial_version"
export STUB_LATEST_VERSION="$partial_version"
export STUB_UPSTREAM_TAG="$partial_version"
: > "$STUB_LOG/gh.calls"
run_update "$partial/ws" || fail "a release with a missing asset must be repaired"
assert_eq "complete" "$(cat "$STUB_RELEASES/v$partial_version")" "missing release asset uploaded"
grep -q "release upload v$partial_version" "$STUB_LOG/gh.calls" \
  || fail "the missing bundle must be uploaded instead of reporting no update"
ok "partial release repaired without a human"

# --- scenario 15: a draft release is finished -------------------------------
echo "scenario: an existing draft release is published"
draft="$(new_workspace draft-release)"
draft_version="$(manifest_version "$draft/ws")"
git -C "$draft/ws" tag "v$draft_version"
git -C "$draft/ws" push -q origin "v$draft_version"
printf '%s\n' draft > "$STUB_RELEASES/v$draft_version"
export STUB_LATEST_VERSION="$draft_version"
export STUB_UPSTREAM_TAG="$draft_version"
: > "$STUB_LOG/gh.calls"
run_update "$draft/ws" || fail "a draft release must be completed"
assert_eq "complete" "$(cat "$STUB_RELEASES/v$draft_version")" "draft release published"
grep -q "release upload v$draft_version" "$STUB_LOG/gh.calls" || fail "draft must receive the bundle"
grep -q "release edit v$draft_version --draft=false" "$STUB_LOG/gh.calls" \
  || fail "draft release must be made public"
ok "draft release uploaded and published"

# --- scenario 16: drift is caught before completing an old release ----------
echo "scenario: upstream drift blocks an incomplete stale release"
stale="$(new_workspace stale-incomplete)"
stale_version="$(manifest_version "$stale/ws")"
export STUB_LATEST_VERSION="$stale_version"
export STUB_UPSTREAM_TAG=9.9.9
: > "$STUB_LOG/gh.calls"
if ( cd "$stale/ws" && bash scripts/actions/auto-update.sh ) > "$WORK/last.log" 2>&1; then
  fail "upstream drift must fail before publishing the stale pinned version"
fi
grep -q 'did not pick the release up' "$WORK/last.log" || fail "the drift guard must explain the miss"
assert_eq "" "$(remote_tag_list "$stale")" "drift must not create a stale tag"
released "v$stale_version" && fail "drift must not publish a stale release"
ok "drift guard also protects incomplete-release recovery"

# --- scenario 17: the updater refuses a manual run from another ref ---------
echo "scenario: a manual updater run from another branch cannot overwrite main"
export STUB_LATEST_VERSION="$keepalive_version"
export STUB_UPSTREAM_TAG="$keepalive_version"
keepalive_commits="$(remote_commits "$keepalive")"
if ( cd "$keepalive/ws" && GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REF=refs/heads/evil \
    bash scripts/actions/auto-update.sh ) > "$WORK/last.log" 2>&1; then
  fail "the updater must refuse to run from a non-main ref"
fi
grep -q 'main' "$WORK/last.log" || fail "the refusal must explain that main is required"
assert_eq "$keepalive_commits" "$(remote_commits "$keepalive")" "wrong-ref run must not push to main"
ok "manual runs are restricted to main"

# --- scenario 18: the tag publisher refuses a branch ref -------------------
echo "scenario: the release publisher refuses a non-version ref"
: > "$STUB_LOG/gh.calls"
if run_publish "$root/ws" main; then
  fail "the release publisher must refuse refs/heads/main"
fi
grep -q 'release create' "$STUB_LOG/gh.calls" && fail "a branch ref must never become a release"
released main && fail "no release named main may be created"
ok "release publishing is restricted to version tags"

echo "PASS: the release pipeline survives replayed history, retries and dry runs"
