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
* `.github/workflows/dependabot-auto-merge.yml`: Automatically merges Dependabot dependency updates after CI tests pass.

## Dependencies

This repository uses the following runtime, build, and CI dependencies:

### Flatpak runtime and base dependencies

| Component | Identifier | Version / Branch | Purpose |
| :--- | :--- | :--- | :--- |
| Runtime | `org.freedesktop.Platform` | `24.08` | Base application execution environment |
| SDK | `org.freedesktop.Sdk` | `24.08` | Build-time compilation tools and headers |
| BaseApp | `org.electronjs.Electron2.BaseApp` | `24.08` | Electron sandbox supervisor and Wayland integration |

### Host and validation tools

| Package | Minimum version | Purpose |
| :--- | :--- | :--- |
| `flatpak` | 1.12.0 | Flatpak application manager and runtime engine |
| `flatpak-builder` | 1.2.0 | Manifest build orchestrator |
| `desktop-file-utils` | 0.26 | Desktop entry specification validator |
| `appstream` / `appstream-util` | 0.16 | AppStream metainfo XML validator |
| `python3` | 3.8+ | Standard library only, used to verify upstream release checksums in CI |

### CI container and GitHub Actions dependencies

All third-party action wrappers were removed in favor of native container execution. Remaining actions are first-party and pinned by immutable commit SHA:

| Dependency | Type | Version / Reference | Immutable commit SHA | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `flatpak-github-actions:gnome-48` | Container image | `gnome-48` | `ghcr.io/flathub-infra/flatpak-github-actions:gnome-48` | Official Flathub build container |
| `actions/checkout` | GitHub Action | `v7.0.1` | `3d3c42e5aac5ba805825da76410c181273ba90b1` | Repository checkout |
| `actions/upload-artifact` | GitHub Action | `v7.0.1` | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` | Upload build bundles in CI |
| `actions/download-artifact` | GitHub Action | `v8.0.1` | `3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c` | Download build bundles for smoke testing |
| `dependabot/fetch-metadata` | GitHub Action | `v3.1.0` | `25dd0e34f4fe68f24cc83900b1fe3fe149efef98` | Dependabot PR metadata extraction |
| `gh` | CLI tool | Pre-installed | Native Go binary | GitHub release publishing |

### Upstream package binaries

| Package | Architecture | Source URL | SHA256 checksum |
| :--- | :--- | :--- | :--- |
| `Filen_linux_amd64.deb` | `x86_64` | `FilenCloudDienste/filen-desktop` | `2c22f9ab466be753824a784e9c63e7d4b48a7e25f1d641ba6304415c35c6ce04` |
| `Filen_linux_arm64.deb` | `aarch64` | `FilenCloudDienste/filen-desktop` | `4a5feed506939d8c9b841473920514b9d900d66c743f43a7a0e984fcc41029d9` |

## Sandbox details

* Packaging method: Repackages the official upstream `.deb` release using `apply_extra` and verifies the package hash during build.
* Display: Uses Wayland with fallback to X11.
* Credentials: Uses the Freedesktop Secret Service (`org.freedesktop.secrets`) and KDE KWallet for session tokens.
* Updates: Disables the in-app electron-updater so Flatpak manages updates.
* Cloud mounts: Uses the embedded rclone binary for local WebDAV and S3 servers.
