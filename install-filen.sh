#!/usr/bin/env bash
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

# Install application icons directly from upstream package (excluding 1024x1024 for Flatpak limits)
for size in 16x16 24x24 32x32 48x48 64x64 128x128 256x256 512x512; do
  if [ -f "usr/share/icons/hicolor/${size}/apps/Filen.png" ]; then
    install -Dm644 "usr/share/icons/hicolor/${size}/apps/Filen.png" "/app/share/icons/hicolor/${size}/apps/io.filen.desktop.png"
  fi
done

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

# Install XDG Desktop entry and AppStream metadata
install -Dm644 io.filen.desktop.desktop -t /app/share/applications/
install -Dm644 io.filen.desktop.metainfo.xml -t /app/share/metainfo/
