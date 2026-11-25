#!/usr/bin/env bash
#
# Offline checks for build/install behavior that differs on Dependabot PRs:
# those runs have no release signing secret, so they must produce and consume
# an unsigned repository rather than attaching a key to an unsigned bundle.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_PARENT="$REPO_ROOT/.tmp"
mkdir -p "$TEST_PARENT"
WORK="$(mktemp -d "$TEST_PARENT/build-install.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

STUBS="$WORK/stubs"
export STUB_LOG="$WORK/flatpak.calls"
mkdir -p "$STUBS" "$WORK/home"
: > "$STUB_LOG"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf '  ok: %s\n' "$*"; }

cat > "$STUBS/flatpak" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$STUB_LOG"
if [[ "${1:-}" == "build-bundle" ]]; then
  for arg in "$@"; do
    [[ "$arg" == *.flatpak ]] && : > "$arg"
  done
fi
STUB
cat > "$STUBS/ostree" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "init" ]]; then
  mkdir -p repo
fi
STUB
chmod +x "$STUBS/flatpak" "$STUBS/ostree"
export PATH="$STUBS:$PATH"

# --- scenario 1: an unsigned build carries no verification key -------------
echo "scenario: a build without the signing secret produces unsigned artifacts"
build="$WORK/build"
mkdir -p "$build"
cp "$REPO_ROOT/scripts/build/build-flatpak.sh" "$REPO_ROOT/filen-public.gpg" "$build/"
: > "$STUB_LOG"
( cd "$build" && env -u GPG_PRIVATE_KEY HOME="$WORK/home" bash build-flatpak.sh ) \
  > "$WORK/build.log" 2>&1 || { cat "$WORK/build.log" >&2; fail "unsigned build must succeed"; }
grep -q -- '--gpg-keys=' "$STUB_LOG" && { cat "$STUB_LOG" >&2; fail "unsigned bundle must not carry a GPG key"; }
grep -q -- '--gpg-import=' "$STUB_LOG" && { cat "$STUB_LOG" >&2; fail "unsigned repo must not import a GPG key"; }
grep -q -- '--gpg-sign=' "$STUB_LOG" && { cat "$STUB_LOG" >&2; fail "unsigned build must not sign"; }
ok "unsigned build omitted all GPG arguments"

# --- scenario 2: the install test follows the repository's actual signature -
echo "scenario: repository install verifies only a signed repository"
repo_ws="$WORK/repo"
mkdir -p "$repo_ws/repo"
cp "$REPO_ROOT/scripts/test/test-repo-install.sh" "$REPO_ROOT/filen-public.gpg" "$repo_ws/"
: > "$STUB_LOG"
( cd "$repo_ws" && bash test-repo-install.sh ) > "$WORK/repo-unsigned.log" 2>&1 \
  || { cat "$WORK/repo-unsigned.log" >&2; fail "unsigned repository install test must succeed"; }
grep -q 'remote-add .*--no-gpg-verify' "$STUB_LOG" \
  || { cat "$STUB_LOG" >&2; fail "unsigned repo must be added with --no-gpg-verify"; }
ok "unsigned repository used --no-gpg-verify"

: > "$repo_ws/repo/summary.sig"
: > "$STUB_LOG"
( cd "$repo_ws" && bash test-repo-install.sh ) > "$WORK/repo-signed.log" 2>&1 \
  || { cat "$WORK/repo-signed.log" >&2; fail "signed repository install test must succeed"; }
grep -q 'remote-add .*--gpg-import=filen-public.gpg' "$STUB_LOG" \
  || { cat "$STUB_LOG" >&2; fail "signed repo must import the tracked public key"; }
ok "signed repository used --gpg-import"

# --- scenario 3: packaging and sandbox checks require the real executable ---
echo "scenario: a missing Filen executable fails packaging and install checks"
grep -Fq '[[ ! -x /app/main/Filen ]]' "$REPO_ROOT/scripts/build/install-filen.sh" \
  || fail "install-filen.sh must reject a package without /app/main/Filen"
for test_script in test-bundle-install.sh test-repo-install.sh; do
  grep -Fq 'flatpak run --command=test io.filen.desktop -x /app/main/Filen' \
    "$REPO_ROOT/scripts/test/$test_script" \
    || fail "$test_script must execute a real file check inside the sandbox"
done
ok "build and install checks require the packaged Filen executable"

echo "PASS: unsigned PR artifacts install and packaged executables are checked"
