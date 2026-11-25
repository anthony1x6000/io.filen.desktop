#!/usr/bin/env bash
#
# Offline tests for scripts/actions/deploy-pages.sh.
#
# The deploy step is driven through stubbed gh/curl so the control flow (waiting
# for the artifact id, minting the OIDC token, creating the deployment, polling
# its status) is verified without touching GitHub.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_PARENT="$REPO_ROOT/.tmp"
mkdir -p "$TEST_PARENT"
WORK="$(mktemp -d "$TEST_PARENT/deploy-pages.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

STUBS="$WORK/stubs"
export STUB_DIR="$WORK/stub-state"
mkdir -p "$STUBS" "$STUB_DIR"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf '  ok: %s\n' "$*"; }

cat > "$STUBS/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
args="$*"
case "$args" in
  *"/actions/runs/"*"/artifacts"*)
    n=$(( $(cat "$STUB_DIR/artifact_calls" 2>/dev/null || echo 0) + 1 ))
    printf '%s\n' "$n" > "$STUB_DIR/artifact_calls"
    if (( n >= ${STUB_ARTIFACT_APPEARS_AT:-1} )); then
      printf '%s\n' "${STUB_ARTIFACT_ID:-424242}"
    fi
    ;;
  *"-X POST"*"/pages/deployments"*)
    cat > "$STUB_DIR/post-body.json"
    printf '{"id": 999, "status": "queued", "page_url": "https://example.test/io.filen.desktop/"}\n'
    ;;
  *"/pages/deployments/"*)
    n=$(( $(cat "$STUB_DIR/status_calls" 2>/dev/null || echo 0) + 1 ))
    printf '%s\n' "$n" > "$STUB_DIR/status_calls"
    # shellcheck disable=SC2086
    set -- ${STUB_STATUS_SEQUENCE:-queued deploying succeed}
    (( n > $# )) && n=$#
    eval "status=\${$n}"
    printf '%s\n' "$status"
    ;;
esac
exit 0
STUB

cat > "$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ -n "${STUB_OIDC_FAIL:-}" ]] && exit 22
printf '{"value": "%s"}\n' "${STUB_OIDC_TOKEN:-stub-oidc-token}"
STUB

chmod +x "$STUBS/gh" "$STUBS/curl"
export PATH="$STUBS:$PATH"

run_deploy() { # extra env via caller; logs to $WORK/last.log
  if ( cd "$REPO_ROOT" && POLL_SECONDS=0 bash scripts/actions/deploy-pages.sh ) \
      > "$WORK/last.log" 2>&1; then
    return 0
  fi
  return 1
}

reset_state() {
  rm -f "$STUB_DIR/artifact_calls" "$STUB_DIR/status_calls" "$STUB_DIR/post-body.json"
}

export GITHUB_REPOSITORY=anthony1x6000/io.filen.desktop
export GITHUB_RUN_ID=45644460922
export GITHUB_SHA=57373f95abb4984754b94765f2c382e92e457a86
export GITHUB_OUTPUT="$WORK/github-output"
export ACTIONS_ID_TOKEN_REQUEST_URL="https://oidc.example.test/token"
export ACTIONS_ID_TOKEN_REQUEST_TOKEN="request-token"
: > "$GITHUB_OUTPUT"

# --- happy path: artifact shows up late, deployment converges ---------------
echo "scenario: artifact appears after retries and the deployment succeeds"
reset_state
export STUB_ARTIFACT_APPEARS_AT=3
run_deploy || { cat "$WORK/last.log" >&2; fail "deploy should succeed"; }
grep -q "on attempt 3" "$WORK/last.log" || fail "should report the retry that found the artifact"
ok "waited for the artifact instead of failing"
grep -q "Pages deployment succeeded" "$WORK/last.log" || fail "should report success"
ok "deployment converged to succeed"
grep -qx "page_url=https://example.test/io.filen.desktop/" "$GITHUB_OUTPUT" \
  || fail "page_url output missing"
ok "page_url exposed as a step output"
python3 - "$STUB_DIR/post-body.json" <<'PY' || fail "deployment payload is wrong"
import json, sys
body = json.load(open(sys.argv[1]))
assert body["artifact_id"] == 424242, body
assert body["pages_build_version"] == "57373f95abb4984754b94765f2c382e92e457a86", body
assert body["oidc_token"] == "stub-oidc-token", body
PY
ok "deployment payload carries artifact id, build version and OIDC token"

# --- artifact never appears -------------------------------------------------
echo "scenario: a missing artifact fails loudly instead of deploying nothing"
reset_state
: > "$GITHUB_OUTPUT"
if ARTIFACT_WAIT_ATTEMPTS=3 STUB_ARTIFACT_APPEARS_AT=99 run_deploy; then
  fail "deploy must fail when the artifact never appears"
fi
grep -q "never appeared" "$WORK/last.log" || fail "should explain the missing artifact"
ok "missing artifact reported"

# --- deployment reports failure --------------------------------------------
echo "scenario: a failed deployment fails the step"
reset_state
: > "$GITHUB_OUTPUT"
if STUB_STATUS_SEQUENCE="queued failed" run_deploy; then
  fail "deploy must fail when the deployment reports failure"
fi
grep -q "Pages deployment failed" "$WORK/last.log" || fail "should surface the failed deployment"
ok "failed deployment reported"

# --- deployment never finishes ---------------------------------------------
echo "scenario: a deployment that never finishes fails the step"
reset_state
: > "$GITHUB_OUTPUT"
if STATUS_WAIT_ATTEMPTS=2 STUB_STATUS_SEQUENCE="queued queued" run_deploy; then
  fail "deploy must fail when the deployment never finishes"
fi
grep -q "did not succeed" "$WORK/last.log" || fail "should explain the unfinished deployment"
ok "unfinished deployment reported"

# --- no OIDC token available ----------------------------------------------
echo "scenario: missing OIDC credentials fail with a clear message"
reset_state
: > "$GITHUB_OUTPUT"
if ( unset ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN; run_deploy ); then
  fail "deploy must fail without OIDC credentials"
fi
grep -q "id-token: write" "$WORK/last.log" || fail "should point at the missing permission"
ok "missing OIDC permission reported"

# --- OIDC minting fails ----------------------------------------------------
echo "scenario: an OIDC minting failure is reported"
reset_state
: > "$GITHUB_OUTPUT"
if STUB_OIDC_FAIL=1 run_deploy; then
  fail "deploy must fail when the OIDC token cannot be minted"
fi
grep -q "could not mint an OIDC token" "$WORK/last.log" || fail "should explain the OIDC failure"
ok "OIDC minting failure reported"

echo "PASS: deploy-pages.sh deploys through the Pages API and fails clearly"
