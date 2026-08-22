#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Flathub runtime remote ==="
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo

if [[ -f repo.tar.gz && ! -d repo ]]; then
  echo "=== Extracting OSTree Repository Archive ==="
  tar -xzf repo.tar.gz
fi

if [[ ! -d repo ]]; then
  echo "::error::OSTree repository directory 'repo' not found!"
  exit 1
fi

REMOTE_NAME="filen-test"
GPG_REMOTE_ARGS=(--no-gpg-verify)
if [[ -f filen-public.gpg ]]; then
  GPG_REMOTE_ARGS=(--gpg-import=filen-public.gpg)
fi

echo "=== Adding OSTree Repository Remote ($REMOTE_NAME) ==="
flatpak remote-add --if-not-exists --user "${GPG_REMOTE_ARGS[@]}" "$REMOTE_NAME" "file://$(pwd)/repo"

echo "=== Querying Remote Repository for Available Applications ==="
flatpak remote-ls --user --show-details "$REMOTE_NAME"

echo "=== Inspecting Remote Application Metadata ==="
flatpak remote-info --user "$REMOTE_NAME" io.filen.desktop

echo "=== Pulling and Installing Application from Repository ==="
flatpak install -y --user --noninteractive "$REMOTE_NAME" io.filen.desktop

echo "=== Verifying Installation Details ==="
flatpak info io.filen.desktop

echo "=== Verifying Application Permissions ==="
flatpak info --show-permissions io.filen.desktop

echo "=== Verifying Application Launch in Sandbox ==="
flatpak run --command=true io.filen.desktop

echo "=== Testing Incremental Pull & Update from Repository ==="
flatpak update -y --user --noninteractive io.filen.desktop

echo "=== Verifying Clean Uninstallation & Remote Cleanup ==="
flatpak uninstall -y --user --noninteractive io.filen.desktop
flatpak remote-delete --user "$REMOTE_NAME"

echo "✓ OSTree repository pull, installation, sandbox execution, and update flow verified successfully!"
