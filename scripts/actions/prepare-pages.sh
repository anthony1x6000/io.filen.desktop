#!/usr/bin/env bash
set -euo pipefail

SITE_DIR="${1:-_site}"

mkdir -p "$SITE_DIR"
if [ -f repo.tar.gz ]; then
  tar -xzf repo.tar.gz -C "$SITE_DIR/"
fi

echo "=== Rendering README.md via GitHub Markdown REST API ==="
python3 - << 'EOF' "$SITE_DIR"
import json
import os
import sys
import urllib.request

site_dir = sys.argv[1]
readme_path = "README.md"

if not os.path.exists(readme_path):
    print(f"::error::File {readme_path} not found!", file=sys.stderr)
    sys.exit(1)

with open(readme_path, "r", encoding="utf-8") as f:
    readme_text = f.read()

api_url = "https://api.github.com/markdown"
headers = {
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "Filen-Flatpak-Pages-Builder",
    "Content-Type": "application/json"
}

token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
if token:
    headers["Authorization"] = f"Bearer {token}"

payload = json.dumps({
    "text": readme_text,
    "mode": "gfm",
    "context": "anthony1x6000/io.filen.desktop"
}).encode("utf-8")

req = urllib.request.Request(api_url, data=payload, headers=headers, method="POST")

try:
    with urllib.request.urlopen(req, timeout=30) as response:
        rendered_html = response.read().decode("utf-8")
except Exception as e:
    print(f"Warning: Failed to render via GitHub API ({e}), using raw text fallback", file=sys.stderr)
    rendered_html = f"<pre>{readme_text}</pre>"

index_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Filen Desktop Flatpak (io.filen.desktop)</title>
</head>
<body>
  <main>
{rendered_html}
  </main>
</body>
</html>
"""

output_file = os.path.join(site_dir, "index.html")
with open(output_file, "w", encoding="utf-8") as f:
    f.write(index_html)

print(f"✓ Rendered {readme_path} to {output_file}")
EOF

# Repository configuration file
cat << 'EOF' > "$SITE_DIR/io.filen.desktop.flatpakrepo"
[Flatpak Repo]
Title=Filen Desktop
Url=https://anthony1x6000.github.io/io.filen.desktop/repo/
Homepage=https://github.com/anthony1x6000/io.filen.desktop
Comment=Unofficial Flatpak builds of Filen desktop client
Description=Automated Flatpak repository for Filen Desktop hosted via GitHub Pages.
Icon=https://avatars.githubusercontent.com/u/79963625?s=200&v=4
EOF

touch "$SITE_DIR/.nojekyll"

echo "✓ GitHub Pages static site successfully prepared in $SITE_DIR!"
