#!/usr/bin/env python3
import re
import sys
import urllib.request

with open("io.filen.desktop.yaml", "r", encoding="utf-8") as f:
    manifest = f.read()

# Match the exact sha256 within the deb release source
amd64_manifest = re.search(r"Filen_linux_amd64\.deb\n\s+sha256:\s+([0-9a-fA-F]{64})", manifest)

if not amd64_manifest:
    print("::error::Could not extract deb sha256 checksum from manifest!", file=sys.stderr)
    sys.exit(1)

manifest_amd64 = amd64_manifest.group(1).lower()

version_match = re.search(r"v(\d+\.\d+\.\d+)/Filen_linux_amd64\.deb", manifest)
version = version_match.group(1) if version_match else "3.0.53"

print(f"=== Verifying Release v{version} Hashes ===")
amd64_url = f"https://github.com/FilenCloudDienste/filen-desktop/releases/download/v{version}/Filen_linux_amd64.deb.sha256.txt"

upstream_amd64 = urllib.request.urlopen(amd64_url, timeout=30).read().decode().strip().split()[0].lower()

print(f"AMD64 Manifest Hash: {manifest_amd64}")
print(f"AMD64 Upstream Hash: {upstream_amd64}")

if manifest_amd64 != upstream_amd64:
    print(f"::error::AMD64 hash mismatch: expected {upstream_amd64}, found {manifest_amd64}", file=sys.stderr)
    sys.exit(1)

print("✓ Release checksum verified successfully!")
