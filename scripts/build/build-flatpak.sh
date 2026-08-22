#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Flathub remote ==="
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "=== Setting up OSTree Repository ==="
mkdir -p repo
ostree init --mode=archive --repo=repo
ostree config --repo=repo set "core.min-free-space-percent" "0"
ostree config --repo=repo set "core.min-free-space-size" "0MB"

GPG_SIGN_BUILD_ARGS=()
GPG_SIGN_REPO_ARGS=()
GPG_BUNDLE_ARGS=()

if [[ -n "${GPG_PRIVATE_KEY:-}" ]]; then
  echo "=== Configuring Automated GPG Pinentry Environment ==="
  export GNUPGHOME="${HOME:-/root}/.gnupg"
  mkdir -p "$GNUPGHOME"
  chmod 700 "$GNUPGHOME"

  # Store passphrase securely for pinentry helper
  if [[ -n "${GPG_PASSPHRASE:-}" ]]; then
    printf "%s" "$GPG_PASSPHRASE" > "$GNUPGHOME/.passphrase"
    chmod 600 "$GNUPGHOME/.passphrase"
  fi

  # Create automated Assuan pinentry responder
  PINENTRY_AUTO="/tmp/pinentry-auto"
  cat << 'EOF' > "$PINENTRY_AUTO"
#!/usr/bin/env python3
import os
import sys

passphrase = os.environ.get("GPG_PASSPHRASE", "")
pass_file = os.path.expanduser("~/.gnupg/.passphrase")
if not passphrase and os.path.exists(pass_file):
    try:
        with open(pass_file, "r", encoding="utf-8") as f:
            passphrase = f.read().rstrip("\r\n")
    except Exception:
        pass

print("OK Pleased to meet you", flush=True)
for line in sys.stdin:
    line = line.strip()
    if line.startswith("GETPIN"):
        print(f"D {passphrase}", flush=True)
        print("OK", flush=True)
    elif line.startswith("BYE"):
        print("OK", flush=True)
        break
    else:
        print("OK", flush=True)
EOF
  chmod 755 "$PINENTRY_AUTO"

  # Configure gpg and gpg-agent to use automated pinentry
  cat << EOF > "$GNUPGHOME/gpg.conf"
use-agent
pinentry-mode loopback
batch
no-tty
EOF

  cat << EOF > "$GNUPGHOME/gpg-agent.conf"
pinentry-program $PINENTRY_AUTO
allow-loopback-pinentry
allow-preset-passphrase
max-cache-ttl 86400
default-cache-ttl 86400
EOF

  # Stop any stale agents and start fresh agent daemon with pinentry provider
  gpgconf --kill all 2>/dev/null || true
  gpg-agent --daemon --pinentry-program "$PINENTRY_AUTO" --homedir "$GNUPGHOME" 2>/dev/null || true

  # Import secret key
  echo "$GPG_PRIVATE_KEY" | gpg --batch --yes --pinentry-mode loopback --passphrase "${GPG_PASSPHRASE:-}" --import

  GPG_KEY_ID=$(gpg --list-secret-keys --with-colons | grep -m1 '^fpr:' | cut -d: -f10)
  echo "Loaded GPG Signing Key: $GPG_KEY_ID"

  # Set ultimate trust
  echo "${GPG_KEY_ID}:6:" | gpg --import-ownertrust 2>/dev/null || true

  GPG_SIGN_BUILD_ARGS=(--gpg-sign="$GPG_KEY_ID")
  GPG_SIGN_REPO_ARGS=(--gpg-sign="$GPG_KEY_ID")
fi

if [[ -f filen-public.gpg ]]; then
  echo "=== Attaching Public GPG Key to Bundle & Repo ==="
  GPG_BUNDLE_ARGS=(--gpg-keys=filen-public.gpg)
  GPG_SIGN_REPO_ARGS+=(--gpg-import=filen-public.gpg)
fi

echo "=== Building Flatpak Application ==="
flatpak-builder \
  --repo=repo \
  --force-clean \
  --disable-cache \
  --install-deps-from=flathub \
  --user \
  --arch=x86_64 \
  --default-branch=master \
  --disable-rofiles-fuse \
  "${GPG_SIGN_BUILD_ARGS[@]}" \
  build-dir \
  io.filen.desktop.yaml

echo "=== Updating OSTree Static Repository & Deltas ==="
flatpak build-update-repo \
  --generate-static-deltas \
  "${GPG_SIGN_REPO_ARGS[@]}" \
  repo

echo "=== Creating Single-File Distribution Bundle ==="
flatpak build-bundle repo io.filen.desktop-x86_64.flatpak io.filen.desktop \
  --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  "${GPG_BUNDLE_ARGS[@]}"

cp io.filen.desktop-x86_64.flatpak io.filen.desktop.flatpak

echo "=== Compressing OSTree Repo for Deployment (Max Compression) ==="
GZIP=-9 tar -czf repo.tar.gz repo
