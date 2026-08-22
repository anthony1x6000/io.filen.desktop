#!/usr/bin/env bash
set -euo pipefail

echo "=== Validating Desktop File ==="
desktop-file-validate io.filen.desktop.desktop

echo "=== Validating AppStream Metainfo ==="
appstream-util validate-relax --nonet io.filen.desktop.metainfo.xml
appstreamcli validate --no-net io.filen.desktop.metainfo.xml

echo "✓ Desktop entry and AppStream metadata valid!"
