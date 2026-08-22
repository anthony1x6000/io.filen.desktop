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
  echo "=== Configuring Headless GPG Environment ==="
  export GNUPGHOME="$(mktemp -d)"
  chmod 700 "$GNUPGHOME"

  # Configure gpg and gpg-agent for headless, batch loopback pinentry
  cat << 'EOF' > "$GNUPGHOME/gpg.conf"
pinentry-mode loopback
use-agent
batch
no-tty
EOF

  cat << 'EOF' > "$GNUPGHOME/gpg-agent.conf"
allow-loopback-pinentry
allow-preset-passphrase
max-cache-ttl 86400
default-cache-ttl 86400
EOF

  # Start gpg-agent
  gpg-connect-agent --homedir "$GNUPGHOME" reloadagent /bye || true
  gpg-connect-agent --homedir "$GNUPGHOME" updatestartuptty /bye || true

  # Import secret key without interactive pinentry prompts
  echo "$GPG_PRIVATE_KEY" | gpg --batch --pinentry-mode loopback --import

  GPG_KEY_ID=$(gpg --list-secret-keys --with-colons | grep -m1 '^fpr:' | cut -d: -f10)
  echo "Loaded GPG Signing Key: $GPG_KEY_ID"

  # Trust key unconditionally in this keyring
  echo "${GPG_KEY_ID}:6:" | gpg --import-ownertrust || true

  GPG_SIGN_BUILD_ARGS=(--gpg-sign="$GPG_KEY_ID" --gpg-homedir="$GNUPGHOME")
  GPG_SIGN_REPO_ARGS=(--gpg-sign="$GPG_KEY_ID" --gpg-homedir="$GNUPGHOME")
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
