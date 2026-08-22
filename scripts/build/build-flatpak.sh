#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Flathub remote ==="
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "=== Setting up OSTree Repository ==="
mkdir -p repo
ostree init --mode=archive --repo=repo
ostree config --repo=repo set "core.min-free-space-percent" "0"
ostree config --repo=repo set "core.min-free-space-size" "0MB"

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
  build-dir \
  io.filen.desktop.yaml

echo "=== Updating OSTree Static Repository & Deltas ==="
flatpak build-update-repo --generate-static-deltas repo

echo "=== Creating Single-File Distribution Bundle ==="
flatpak build-bundle repo io.filen.desktop-x86_64.flatpak io.filen.desktop \
  --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo

cp io.filen.desktop-x86_64.flatpak io.filen.desktop.flatpak

echo "=== Compressing OSTree Repo for Deployment (Max Compression) ==="
GZIP=-9 tar -czf repo.tar.gz repo
