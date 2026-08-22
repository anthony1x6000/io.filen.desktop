#!/usr/bin/env bash
set -euo pipefail

BUNDLE_FILE="${1:-io.filen.desktop-x86_64.flatpak}"

echo "=== Setting up Flathub remote ==="
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "=== Installing Flatpak Bundle ($BUNDLE_FILE) ==="
flatpak install -y --user --noninteractive "$BUNDLE_FILE"

echo "=== Verifying Installation Metadata ==="
flatpak info io.filen.desktop

echo "=== Verifying Application Permissions ==="
flatpak info --show-permissions io.filen.desktop

echo "=== Verifying Application Launch in Sandbox ==="
flatpak run --command=true io.filen.desktop

echo "=== Verifying Clean Uninstallation ==="
flatpak uninstall -y --user --noninteractive io.filen.desktop

echo "✓ Standalone bundle installation, sandbox execution, and removal verified!"
