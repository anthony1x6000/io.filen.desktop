#!/usr/bin/env bash
#
# Deploy an already-uploaded Pages artifact through the documented Pages
# deployment REST API.
#
# actions/deploy-pages v5 resolves the artifact through the artifact service,
# whose listing lags behind the upload by an unpredictable amount. Deploying
# right after uploading then fails intermittently with:
#
#   Fetching artifact metadata for "github-pages" in this workflow run
#   Found 2 artifact(s)
#   Error: No artifacts named "github-pages" were found for this workflow run.
#
# The run's REST artifact list does not lag, so the artifact id is resolved
# from there, and the deployment is created and polled directly.
#
# Requires: pages: write, id-token: write, actions: read.
set -euo pipefail

ARTIFACT_NAME="${ARTIFACT_NAME:-github-pages}"
ARTIFACT_WAIT_ATTEMPTS="${ARTIFACT_WAIT_ATTEMPTS:-24}"
STATUS_WAIT_ATTEMPTS="${STATUS_WAIT_ATTEMPTS:-60}"
POLL_SECONDS="${POLL_SECONDS:-5}"

log() { printf '%s\n' "$*"; }
die() { printf '::error::%s\n' "$*" >&2; exit 1; }

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"

artifact_id=""
for attempt in $(seq 1 "$ARTIFACT_WAIT_ATTEMPTS"); do
  artifact_id="$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/artifacts" \
    --jq ".artifacts[] | select(.name == \"${ARTIFACT_NAME}\") | .id" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$artifact_id" ]]; then
    log "Found artifact '${ARTIFACT_NAME}' (id ${artifact_id}) on attempt ${attempt}"
    break
  fi
  log "Artifact '${ARTIFACT_NAME}' not listed yet (attempt ${attempt}/${ARTIFACT_WAIT_ATTEMPTS})"
  sleep "$POLL_SECONDS"
done
[[ -n "$artifact_id" ]] || die "artifact '${ARTIFACT_NAME}' never appeared in run ${GITHUB_RUN_ID}"

if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" || -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]]; then
  die "no OIDC token request available; the job needs 'id-token: write'"
fi
oidc_token="$(curl -sS -f -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}" | jq -r '.value // empty')" \
  || die "could not mint an OIDC token"
[[ -n "$oidc_token" ]] || die "could not mint an OIDC token"

payload="$(jq -n --argjson artifact_id "$artifact_id" --arg version "$GITHUB_SHA" \
  --arg token "$oidc_token" \
  '{artifact_id: $artifact_id, pages_build_version: $version, oidc_token: $token}')"

# The Pages API intermittently answers 5xx with an empty body (which gh reports
# as "unexpected end of JSON input"), so a transient failure is retried instead
# of failing the deploy.
deployment=""
create_attempts="${CREATE_WAIT_ATTEMPTS:-5}"
for attempt in $(seq 1 "$create_attempts"); do
  if deployment="$(printf '%s' "$payload" \
      | gh api -X POST "repos/${GITHUB_REPOSITORY}/pages/deployments" --input - 2>"$WORKDIR/create.err")" \
      && [[ -n "$deployment" ]]; then
    break
  fi
  log "creating the Pages deployment failed (attempt ${attempt}/${create_attempts}): $(tr '\n' ' ' < "$WORKDIR/create.err" | head -c 200)"
  deployment=""
  if (( attempt < create_attempts )); then
    sleep "$POLL_SECONDS"
  fi
done
[[ -n "$deployment" ]] || die "creating the Pages deployment failed after ${create_attempts} attempt(s)"

deployment_id="$(jq -r '.id // empty' <<<"$deployment")"
page_url="$(jq -r '.page_url // empty' <<<"$deployment")"
[[ -n "$deployment_id" ]] || die "Pages deployment was not created: ${deployment}"
log "Created Pages deployment ${deployment_id}"

status=""
for attempt in $(seq 1 "$STATUS_WAIT_ATTEMPTS"); do
  status="$(gh api "repos/${GITHUB_REPOSITORY}/pages/deployments/${deployment_id}" \
    --jq '.status' 2>/dev/null || true)"
  case "$status" in
    succeed) log "Pages deployment succeeded"; break ;;
    failed|cancelled) die "Pages deployment ${status}" ;;
  esac
  log "Pages deployment status: ${status:-unknown} (attempt ${attempt}/${STATUS_WAIT_ATTEMPTS})"
  sleep "$POLL_SECONDS"
done
[[ "$status" == "succeed" ]] || die "Pages deployment did not succeed (last status: ${status:-unknown})"

if [[ -n "$page_url" ]]; then
  printf 'page_url=%s\n' "$page_url" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
  log "Deployed to ${page_url}"
fi
