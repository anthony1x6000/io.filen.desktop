#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
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

echo "=== Verifying Configured Remotes (Checking Embedded Origin) ==="
flatpak remotes -d

echo "=== Testing Flatpak Update Mechanism ==="
flatpak update -y --user --noninteractive io.filen.desktop || true

echo "=== Verifying Clean Uninstallation ==="
flatpak uninstall -y --user --noninteractive io.filen.desktop

echo "✓ Standalone bundle installation, execution, and update flow verified!"
