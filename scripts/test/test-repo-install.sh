#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Flathub runtime remote ==="
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "=== Extracting OSTree Repository Archive ==="
tar -xzf repo.tar.gz

echo "=== Adding Local OSTree Repository Remote ==="
flatpak remote-add --if-not-exists --user --no-gpg-verify filen-local "file://$(pwd)/repo"

echo "=== Installing Application from Local Repository ==="
flatpak install -y --user --noninteractive filen-local io.filen.desktop

echo "=== Verifying Installation Metadata ==="
flatpak info io.filen.desktop

echo "=== Verifying Application Permissions ==="
flatpak info --show-permissions io.filen.desktop

echo "=== Verifying Application Launch in Sandbox ==="
flatpak run --command=true io.filen.desktop

echo "=== Testing Incremental Flatpak Update from Repository ==="
flatpak update -y --user --noninteractive io.filen.desktop

echo "=== Verifying Clean Uninstallation ==="
flatpak uninstall -y --user --noninteractive io.filen.desktop
flatpak remote-delete --user filen-local

echo "✓ OSTree repository installation, execution, and update flow verified!"
