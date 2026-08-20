# Filen desktop Flatpak (`io.filen.desktop`)

Flatpak build files and packaging for the Filen desktop client (`io.filen.desktop`).

## Prerequisites

### For local builds

Install Flatpak and flatpak-builder using your package manager:

```bash
# Debian, Ubuntu, Pop!_OS
sudo apt install -y flatpak flatpak-builder

# Fedora, RHEL
sudo dnf install -y flatpak flatpak-builder

# Arch Linux, Manjaro
sudo pacman -S flatpak flatpak-builder
```

Add the Flathub remote and install the runtime dependencies:

```bash
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub \
  org.freedesktop.Platform//24.08 \
  org.freedesktop.Sdk//24.08 \
  org.electronjs.Electron2.BaseApp//24.08
```

### For GitHub Actions

You do not need to install anything locally. The workflows run in GitHub-hosted Ubuntu runners.

## Directory configuration

Filen needs access to your local folders to sync files. Allowed paths and defaults are set in `filen-directories.conf`:

* System template: `/app/etc/filen-directories.conf`
* User config: `~/.config/filen/directories.conf` (created on first run if missing)

```ini
# Primary sync folder
FILEN_SYNC_ROOT="$HOME/Filen"

# Colon-separated list of allowed sync directories
FILEN_ALLOWED_DIRS="$HOME/Documents:$HOME/Downloads:$HOME/Pictures:$HOME/Videos:$HOME/Music:$HOME/Projects"

# Create the sync root if it does not exist
FILEN_AUTO_CREATE_SYNC_ROOT=true

# Cache location
FILEN_CACHE_DIR="$HOME/.var/app/io.filen.desktop/cache"

# Virtual drive mount point
FILEN_MOUNT_POINT="$HOME/FilenDrive"

# Log warnings when syncing outside the allowed list
FILEN_STRICT_DIRECTORY_CHECK=false
```

To grant access to directories on external drives or secondary mounts, use Flatpak overrides:

```bash
flatpak override --user --filesystem=/media/storage io.filen.desktop
```

## Build and install locally

Build and install the application:

```bash
flatpak-builder --force-clean --user --install-deps-from=flathub --install build-dir io.filen.desktop.yaml
```

Run the application:

```bash
flatpak run io.filen.desktop
```

Create a standalone `.flatpak` bundle file:

```bash
flatpak-builder --repo=repo --force-clean build-dir io.filen.desktop.yaml
flatpak build-bundle repo io.filen.desktop.flatpak io.filen.desktop --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo
```

## GitHub Actions workflows

* `.github/workflows/build.yml`: Verifies the upstream deb SHA256 hashes against `io.filen.desktop.yaml`, checks AppStream metadata, and builds the Flatpak package on pull requests and pushes.
* `.github/workflows/release.yml`: Builds and uploads a `.flatpak` bundle to GitHub Releases when you push a version tag (`v*`).

## Sandbox details

* Packaging method: Repackages the official upstream `.deb` release using `apply_extra` and verifies the package hash during build.
* Display: Uses Wayland with fallback to X11.
* Credentials: Uses the Freedesktop Secret Service (`org.freedesktop.secrets`) and KDE KWallet for session tokens.
* Updates: Disables the in-app electron-updater so Flatpak manages updates.
* Cloud mounts: Uses the embedded rclone binary for local WebDAV and S3 servers.
