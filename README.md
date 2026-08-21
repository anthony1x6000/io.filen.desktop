# Filen desktop Flatpak (`io.filen.desktop`)

**Warning**: This is an unofficial Flatpak build of Filen, generated from the official Filen-built .deb packages here: https://filen.io/products/desktop

Flatpak build files and packaging for the Filen desktop client (`io.filen.desktop`).

## Table of contents

- [Prerequisites](#prerequisites)
  - [For local builds](#for-local-builds)
  - [For GitHub Actions](#for-github-actions)
- [Installation](#installation)
- [Sandbox permissions and Flatseal](#sandbox-permissions-and-flatseal)
  - [Granting access to additional folders (Flatseal)](#granting-access-to-additional-folders-flatseal)
- [Build and install locally](#build-and-install-locally)
- [GitHub Actions workflows](#github-actions-workflows)
- [Repository scripts](#repository-scripts)
- [Dependencies](#dependencies)
  - [Flatpak runtime and base dependencies](#flatpak-runtime-and-base-dependencies)
  - [Host and validation tools](#host-and-validation-tools)
  - [CI container and GitHub Actions dependencies](#ci-container-and-github-actions-dependencies)
  - [Upstream package binaries](#upstream-package-binaries)
- [Sandbox details](#sandbox-details)
- [License](#license)

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

## Installation

Download the latest `io.filen.desktop.flatpak` single-file bundle from [GitHub Releases](https://github.com/anthony1x6000/io.filen.desktop/releases), then install:

```bash
flatpak install --user io.filen.desktop.flatpak
```

Or install directly from the release URL:

```bash
flatpak install --user https://github.com/anthony1x6000/io.filen.desktop/releases/latest/download/io.filen.desktop.flatpak
```

Run the application:

```bash
flatpak run io.filen.desktop
```

## Sandbox permissions and Flatseal

By default, the Flatpak sandbox is strictly isolated with minimal filesystem privileges:

* **Host filesystem access:** Restricted strictly to `~/Downloads` (`xdg-download`).
* **Application data & session state:** Securely isolated inside `~/.var/app/io.filen.desktop/`.
* **Hardware acceleration:** DRI (`--device=dri`).
* **Credentials:** Freedesktop Secret Service & KDE KWallet D-Bus interfaces.

### Granting access to additional folders (Flatseal)

If you want to sync folders outside of `~/Downloads` (such as `~/Documents`, `~/Projects`, or external storage drives):

1. **Using Flatseal (graphical interface):**
   * Open **Flatseal** and select **Filen**.
   * Scroll down to the **Filesystem** section -> **Other files**.
   * Click **+** (Add) and specify your desired folder path (e.g. `~/Documents` or `/media/storage`).

2. **Using the command line:**
   ```bash
   flatpak override --user --filesystem=~/Documents io.filen.desktop
   flatpak override --user --filesystem=/media/storage io.filen.desktop
   ```

## Build and install locally

Build and install the application directly into your local Flatpak environment:

```bash
flatpak-builder --force-clean --user --install-deps-from=flathub --install build-dir io.filen.desktop.yaml
```

Run the application:

```bash
flatpak run io.filen.desktop
```

Or build the standalone `.flatpak` bundle:

```bash
bash scripts/build-flatpak.sh
```

## GitHub Actions workflows

* `.github/workflows/build.yml`: Verifies upstream deb SHA256 hashes against `io.filen.desktop.yaml`, checks AppStream metadata, builds the Flatpak package, and verifies local bundle installation and execution.
* `.github/workflows/release.yml`: Builds and uploads a standalone `.flatpak` bundle to GitHub Releases when you push a version tag (`v*`).
* `.github/workflows/auto-update-and-release.yml`: Checks for new upstream releases from Filen daily at midnight UTC via `flatpak-external-data-checker`, bumps version numbers and checksums, and tags new releases.
* `.github/workflows/dependabot-auto-merge.yml`: Automatically merges Dependabot dependency updates after CI tests pass.

## Repository scripts

All build, test, and automation logic is decoupled into independent script files with zero embedded scripting in manifests or workflows:

* `install-filen.sh`: Package extraction, hicolor icon installation, cross-architecture binary stripping, and application installation logic executed during `flatpak-builder`.
* `scripts/validate-metadata.sh`: Validates desktop entry syntax and AppStream metadata specification compliance.
* `scripts/verify-checksums.py`: Verifies upstream release sha256 checksums from GitHub against the manifest.
* `scripts/build-flatpak.sh`: Initializes the repository, compiles the application with `flatpak-builder`, and generates the standalone `.flatpak` distribution bundle.
* `scripts/test-bundle-install.sh`: Smoke-tests standalone `.flatpak` bundle installation, permissions, sandbox execution, and uninstallation.
* `scripts/publish-release.sh`: Publishes GitHub releases and attaches the Flatpak bundle via `gh`.
* `scripts/update-metainfo.py`: Adds new release version entries to `io.filen.desktop.metainfo.xml`.
* `scripts/auto-update.sh`: Orchestrates upstream update polling, version bumping, building, tagging, and releasing.
* `scripts/auto-merge-dependabot.sh`: Approves and enables auto-merge on validated Dependabot PRs.

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

## Sandbox details

* Packaging method: Repackages the upstream `.deb` release during build time with verified cryptographic checksums, producing fully standalone Flatpak bundles.
* Display: Uses Wayland with fallback to X11.
* Credentials: Uses the Freedesktop Secret Service (`org.freedesktop.secrets`) and KDE KWallet for session tokens.
* Updates: Disables the in-app electron-updater so Flatpak manages updates.
* Cloud mounts: Uses the embedded rclone binary for local WebDAV and S3 servers.

## License

This repository and all associated scripts are licensed under the [GNU Affero General Public License v3.0](LICENSE) (`AGPL-3.0-only`).
