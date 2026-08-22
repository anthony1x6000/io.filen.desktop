#!/usr/bin/env bash
set -euo pipefail

SITE_DIR="${1:-_site}"

mkdir -p "$SITE_DIR"
if [ -f repo.tar.gz ]; then
  tar -xzf repo.tar.gz -C "$SITE_DIR/"
fi

echo "=== Dynamically pulling raw README.md and rendering via GitHub Markdown REST API ==="
python3 - << 'EOF' "$SITE_DIR"
import json
import os
import re
import subprocess
import sys
import urllib.request

site_dir = sys.argv[1]

# 1. Dynamically resolve GitHub repository (<owner>/<repo>)
repo = os.environ.get("GITHUB_REPOSITORY")
if not repo:
    try:
        remote_url = subprocess.check_output(
            ["git", "config", "--get", "remote.origin.url"], text=True
        ).strip()
        m = re.search(r"github\.com[:/]([^/]+)/(.+?)(?:\.git)?$", remote_url)
        if m:
            repo = f"{m.group(1)}/{m.group(2)}"
    except Exception:
        pass

if not repo:
    repo = "anthony1x6000/io.filen.desktop"

owner, repo_name = repo.split("/", 1)

# 2. Dynamically resolve branch or ref
ref = os.environ.get("GITHUB_REF_NAME") or os.environ.get("GITHUB_SHA")
if not ref:
    try:
        ref = subprocess.check_output(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"], text=True
        ).strip()
        if ref == "HEAD":
            ref = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    except Exception:
        ref = "main"

print(f"Target repository: {repo} (ref: {ref})")

# 3. Pull README dynamically as raw file from GitHub
token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
raw_url = f"https://raw.githubusercontent.com/{repo}/{ref}/README.md"
auth_headers = {"User-Agent": "Filen-Flatpak-Pages-Builder"}
if token:
    auth_headers["Authorization"] = f"Bearer {token}"

readme_text = None
try:
    print(f"Fetching raw README from: {raw_url}")
    req_raw = urllib.request.Request(raw_url, headers=auth_headers)
    with urllib.request.urlopen(req_raw, timeout=30) as resp:
        readme_text = resp.read().decode("utf-8")
    print(f"✓ Dynamically fetched {len(readme_text)} bytes from raw repository URL")
except Exception as e:
    print(f"Notice: Could not fetch from raw URL ({e}), falling back to local README.md", file=sys.stderr)
    if os.path.exists("README.md"):
        with open("README.md", "r", encoding="utf-8") as f:
            readme_text = f.read()

if not readme_text:
    print("::error::Could not retrieve README content from remote or local!", file=sys.stderr)
    sys.exit(1)

# 4. Render markdown using GitHub REST API endpoint
api_url = "https://api.github.com/markdown"
api_headers = {
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "Filen-Flatpak-Pages-Builder",
    "Content-Type": "application/json"
}
if token:
    api_headers["Authorization"] = f"Bearer {token}"

payload = json.dumps({
    "text": readme_text,
    "mode": "gfm",
    "context": repo
}).encode("utf-8")

req_api = urllib.request.Request(api_url, data=payload, headers=api_headers, method="POST")

try:
    with urllib.request.urlopen(req_api, timeout=30) as response:
        rendered_html = response.read().decode("utf-8")
    print(f"✓ Successfully rendered markdown via GitHub Markdown REST API ({len(rendered_html)} bytes HTML)")
except Exception as e:
    print(f"Warning: Failed to render via GitHub API ({e}), using raw fallback", file=sys.stderr)
    rendered_html = f"<pre>{readme_text}</pre>"

# 5. Output pure semantic HTML without CSS
index_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Filen Desktop Flatpak ({repo_name})</title>
</head>
<body>
  <main>
{rendered_html}
  </main>
</body>
</html>
"""

output_html_file = os.path.join(site_dir, "index.html")
with open(output_html_file, "w", encoding="utf-8") as f:
    f.write(index_html)

# 6. Dynamically write Flatpak repository configuration file
flatpakrepo_content = f"""[Flatpak Repo]
Title=Filen Desktop
Url=https://{owner}.github.io/{repo_name}/repo/
Homepage=https://github.com/{repo}
Comment=Unofficial Flatpak builds of Filen desktop client
Description=Automated Flatpak repository for Filen Desktop hosted via GitHub Pages.
Icon=https://avatars.githubusercontent.com/u/79963625?s=200&v=4
gpg-verify=false
"""

output_repo_file = os.path.join(site_dir, f"{repo_name}.flatpakrepo")
with open(output_repo_file, "w", encoding="utf-8") as f:
    f.write(flatpakrepo_content)

print(f"✓ Generated {output_html_file} and {output_repo_file}")
EOF

touch "$SITE_DIR/.nojekyll"

echo "✓ GitHub Pages static site successfully prepared in $SITE_DIR!"
