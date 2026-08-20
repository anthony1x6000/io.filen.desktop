#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
set -euo pipefail

# Extract Debian package contents
mkdir -p /app/main
ar x filen.deb
tar xf data.tar.*

if [ -d opt/Filen ]; then
  cp -a opt/Filen/* /app/main/
elif [ -d usr/lib/filen ]; then
  cp -a usr/lib/filen/* /app/main/
elif [ -d opt/filen ]; then
  cp -a opt/filen/* /app/main/
fi

rm -rf data.tar.* control.tar.* debian-binary usr opt
patch-desktop-filename /app/main/resources/app.asar 2>/dev/null || true

# Strip unused architecture and libc variants bundled in upstream package
rm -rf /app/main/resources/app.asar.unpacked/bin/rclone/rclone-linux-arm64
rm -rf /app/main/resources/app.asar.unpacked/node_modules/@napi-rs/canvas-linux-x64-musl
rm -rf /app/main/resources/app.asar.unpacked/node_modules/@napi-rs/canvas-linux-arm64*
rm -f /app/main/resources/app.asar.unpacked/node_modules/@msgpackr-extract/msgpackr-extract-linux-x64/*.musl.node
rm -f /app/main/chrome-sandbox

# Install launcher binary
install -Dm755 filen.sh /app/bin/filen

# Install configuration defaults
install -Dm644 filen-directories.conf -t /app/etc/

# Install XDG Desktop entry and AppStream metadata
install -Dm644 io.filen.desktop.desktop -t /app/share/applications/
install -Dm644 io.filen.desktop.metainfo.xml -t /app/share/metainfo/

# Install application icons
install -Dm644 16x16.png /app/share/icons/hicolor/16x16/apps/io.filen.desktop.png
install -Dm644 24x24.png /app/share/icons/hicolor/24x24/apps/io.filen.desktop.png
install -Dm644 32x32.png /app/share/icons/hicolor/32x32/apps/io.filen.desktop.png
install -Dm644 48x48.png /app/share/icons/hicolor/48x48/apps/io.filen.desktop.png
install -Dm644 64x64.png /app/share/icons/hicolor/64x64/apps/io.filen.desktop.png
install -Dm644 128x128.png /app/share/icons/hicolor/128x128/apps/io.filen.desktop.png
install -Dm644 256x256.png /app/share/icons/hicolor/256x256/apps/io.filen.desktop.png
install -Dm644 512x512.png /app/share/icons/hicolor/512x512/apps/io.filen.desktop.png
