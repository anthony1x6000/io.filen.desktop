#!/usr/bin/env bash
#
# Offline regression suite for scripts/validate/verify-checksums.py.
#
# The verifier used to fall back to a hardcoded release version whenever the
# manifest did not name one, so an unparsable manifest was silently checked
# against an old release and the run failed on a checksum mismatch that pointed
# at the wrong cause.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_PARENT="$REPO_ROOT/.tmp"
mkdir -p "$TEST_PARENT"
WORK="$(mktemp -d "$TEST_PARENT/verify-checksums.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf '  ok: %s\n' "$*"; }

SHA="$(printf 'a%.0s' {1..64})"

echo "scenario: manifest does not name a release version"
BROKEN="$WORK/no-version"
mkdir -p "$BROKEN"
cat > "$BROKEN/io.filen.desktop.yaml" <<EOF
modules:
  - name: filen
    sources:
      - type: file
        dest-filename: filen.deb
        url: https://example.invalid/Filen_linux_amd64.deb
        sha256: ${SHA}
EOF

if ( cd "$BROKEN" && python3 "$REPO_ROOT/scripts/validate/verify-checksums.py" ) >"$WORK/out.log" 2>&1; then
  fail "verifier accepted a manifest that names no release version"
fi

if ! grep -qiE 'version' "$WORK/out.log"; then
  cat "$WORK/out.log" >&2
  fail "verifier did not report the unparsable release version"
fi

if grep -qi 'hash mismatch' "$WORK/out.log"; then
  cat "$WORK/out.log" >&2
  fail "verifier blamed the checksum for an unparsable version"
fi

ok "unparsable version fails on the manifest, not on a checksum mismatch"

echo "✓ verify-checksums rejects a manifest without a release version"
