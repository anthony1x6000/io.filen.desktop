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
    if [[ "$arg" == *.flatpak ]]; then
      : > "$arg"
    fi
  done
fi
exit 0
STUB
cat > "$STUBS/ostree" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "init" ]]; then
  mkdir -p repo
fi
STUB
chmod +x "$STUBS/flatpak" "$STUBS/ostree"
ln -s flatpak "$STUBS/flatpak-builder"
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

echo "scenario: publishing builds refuse to run unsigned"
: > "$STUB_LOG"
if ( cd "$build" && env -u GPG_PRIVATE_KEY REQUIRE_SIGNING=1 HOME="$WORK/home" \
    bash build-flatpak.sh ) > "$WORK/required-signing.log" 2>&1; then
  fail "a publishing build must fail when the signing secret is missing"
fi
grep -q 'signing is required' "$WORK/required-signing.log" \
  || { cat "$WORK/required-signing.log" >&2; fail "missing signing key must be explained"; }
ok "publishing build rejected a missing signing key"

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

# --- scenario 4: Pages never advertises a key for an unsigned repo ----------
echo "scenario: Pages preparation rejects an unsigned repository with a key"
cat > "$STUBS/python3" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$STUBS/python3"
pages="$WORK/pages"
mkdir -p "$pages/repo"
tar -czf "$pages/repo.tar.gz" -C "$pages" repo
cp "$REPO_ROOT/filen-public.gpg" "$REPO_ROOT/README.md" "$pages/"
if ( cd "$pages" && GITHUB_REPOSITORY=anthony1x6000/io.filen.desktop \
    bash "$REPO_ROOT/scripts/actions/prepare-pages.sh" _site ) > "$WORK/pages.log" 2>&1; then
  fail "Pages must not advertise a GPG key for an unsigned repository"
fi
grep -qi 'unsigned' "$WORK/pages.log" \
  || { cat "$WORK/pages.log" >&2; fail "unsigned Pages repository must be rejected clearly"; }
ok "unsigned Pages repository cannot advertise a verification key"

echo "PASS: unsigned PR artifacts install and packaged executables are checked"
