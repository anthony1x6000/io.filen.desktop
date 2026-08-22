#!/usr/bin/env bash
set -euo pipefail

SITE_DIR="${1:-_site}"

mkdir -p "$SITE_DIR"
tar -xzf repo.tar.gz -C "$SITE_DIR/"

# Web landing page with pure native HTML and zero CSS
cat << 'EOF' > "$SITE_DIR/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Filen Desktop Flatpak Repository</title>
</head>
<body>
  <h1>Filen Desktop Flatpak Repository</h1>
  <p>Automated Flatpak repository hosting builds of the Filen desktop client.</p>

  <h2>1. Add the repository</h2>
  <p>Add this repository to your local Flatpak installation:</p>
  <pre><code>flatpak remote-add --if-not-exists --user filen https://anthony1x6000.github.io/io.filen.desktop/io.filen.desktop.flatpakrepo</code></pre>

  <h2>2. Install Filen Desktop</h2>
  <p>Install the application from the repository:</p>
  <pre><code>flatpak install --user filen io.filen.desktop</code></pre>

  <h2>3. Automatic updates</h2>
  <p>Once installed, update Filen Desktop with your other Flatpak packages at any time:</p>
  <pre><code>flatpak update</code></pre>

  <hr>
  <p>Source code and build workflows available on <a href="https://github.com/anthony1x6000/io.filen.desktop">GitHub</a>.</p>
</body>
</html>
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

echo "✓ GitHub Pages site prepared successfully in $SITE_DIR!"
