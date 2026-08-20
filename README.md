# Filen Desktop - Flatpak Packaging (`io.filen.desktop`)

Flatpak packaging repository and automated CI/CD workflows for **[Filen Desktop](https://filen.io)** (`io.filen.desktop`), an open-source, client-side end-to-end encrypted cloud storage and synchronization client.

---

## Table of Contents

- [Prerequisites (What to Install)](#prerequisites-what-to-install)
  - [Local Machine Requirements](#local-machine-requirements)
  - [GitHub Actions Requirements](#github-actions-requirements)
- [Directory Configuration (`directories.conf`)](#directory-configuration-directoriesconf)
  - [Configuration File Options](#configuration-file-options)
  - [Granting Additional Sandbox Permissions](#granting-additional-sandbox-permissions)
- [Building & Installing Locally](#building--installing-locally)
  - [1. Set Up the Flathub Remote](#1-set-up-the-flathub-remote)
  - [2. Install Runtime and BaseApp Dependencies](#2-install-runtime-and-baseapp-dependencies)
  - [3. Build and Install the Flatpak](#3-build-and-install-the-flatpak)
  - [4. Run the Application](#4-run-the-application)
  - [5. Create a Single-File Bundle](#5-create-a-single-file-bundle)
- [Automated Builds with GitHub Actions](#automated-builds-with-github-actions)
- [Repository Structure](#repository-structure)
- [Sandboxing & Architecture Details](#sandboxing--architecture-details)

---

## Prerequisites (What to Install)

### Local Machine Requirements

If you wish to build, test, and run the Flatpak locally on your system, install the following packages using your distribution's package manager:

#### 1. Core Tools
* **`flatpak`** (>= 1.12.0)
* **`flatpak-builder`** (>= 1.2.0)

##### Installation by Distribution:
```bash
# Ubuntu / Debian / Pop!_OS
sudo apt update
sudo apt install -y flatpak flatpak-builder

# Fedora / RHEL
sudo dnf install -y flatpak flatpak-builder

# Arch Linux / Manjaro
sudo pacman -S flatpak flatpak-builder

# openSUSE
sudo zypper install flatpak flatpak-builder
```

#### 2. Optional Validation & Linting Tools
To validate desktop entries and AppStream metadata:
```bash
# Ubuntu / Debian
sudo apt install -y desktop-file-utils appstream appstream-util

# Fedora
sudo dnf install -y desktop-file-utils libappstream-glib appstream
```

### GitHub Actions Requirements

**Nothing needs to be installed locally for CI/CD.**
The included GitHub Actions workflows (`.github/workflows/build.yml` and `.github/workflows/release.yml`) run inside GitHub-hosted `ubuntu-latest` virtual environments with containerized Flatpak builders automatically configured.

---

## Directory Configuration (`directories.conf`)

Allowed synchronization folders, cache directories, and virtual drive mount paths are managed through a configuration file.

### Configuration File Locations

1. **System Default (Read-Only):** `/app/etc/filen-directories.conf`
2. **User Override (Editable):** `~/.config/filen/directories.conf` *(Auto-generated on first launch if missing)*

### Configuration File Options

```ini
# ==============================================================================
# Filen Desktop Flatpak - Directory Configuration
# ==============================================================================

# Primary synchronization root directory.
FILEN_SYNC_ROOT="$HOME/Filen"

# Explicitly allowed directories for selective synchronization (colon-separated).
FILEN_ALLOWED_DIRS="$HOME/Documents:$HOME/Downloads:$HOME/Pictures:$HOME/Videos:$HOME/Music:$HOME/Projects"

# Automatically create the sync root directory if it does not exist (true/false)
FILEN_AUTO_CREATE_SYNC_ROOT=true

# Custom cache directory location
FILEN_CACHE_DIR="$HOME/.var/app/io.filen.desktop/cache"

# Virtual Drive Mount Point (FUSE / WebDAV mount path)
FILEN_MOUNT_POINT="$HOME/FilenDrive"

# Strict directory isolation check (true/false)
FILEN_STRICT_DIRECTORY_CHECK=false
```

### Granting Additional Sandbox Permissions

By default, the Flatpak manifest includes `--filesystem=host` to allow full access to user storage drives. If you run under restricted sandboxing or wish to explicitly grant access to custom mount points (such as an external hard drive or secondary volume):

```bash
# Allow access to an external media drive
flatpak override --user --filesystem=/media/data/Storage io.filen.desktop

# Allow access to an NFS/SMB mount
flatpak override --user --filesystem=/mnt/nas io.filen.desktop

# View current overrides
flatpak override --user --show io.filen.desktop

# Reset overrides
flatpak override --user --reset io.filen.desktop
```

---

## Building & Installing Locally

### 1. Set Up the Flathub Remote

Ensure the Flathub repository is configured for your user or system:

```bash
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

### 2. Install Runtime and BaseApp Dependencies

Install the required Freedesktop platform, SDK, and Electron BaseApp:

```bash
flatpak install --user flathub \
  org.freedesktop.Platform//24.08 \
  org.freedesktop.Sdk//24.08 \
  org.electronjs.Electron2.BaseApp//24.08
```

### 3. Build and Install the Flatpak

Execute `flatpak-builder` from this repository:

```bash
flatpak-builder --force-clean --user --install-deps-from=flathub --install build-dir io.filen.desktop.yaml
```

### 4. Run the Application

Launch the installed Flatpak:

```bash
flatpak run io.filen.desktop
```

To run with verbose output or custom arguments:

```bash
flatpak run io.filen.desktop --log-level=debug
```

### 5. Create a Single-File Bundle

To create a standalone `.flatpak` bundle for offline distribution or transfer:

```bash
flatpak-builder --repo=repo --force-clean build-dir io.filen.desktop.yaml
flatpak build-bundle repo io.filen.desktop.flatpak io.filen.desktop --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo
```

The recipient can install it with:

```bash
flatpak install --user io.filen.desktop.flatpak
```

---

## Automated Builds with GitHub Actions

This repository includes two GitHub Actions workflows located in `.github/workflows/`:

1. **`build.yml` (Continuous Integration):**
   - Triggers on every push and pull request to `main` / `master`.
   - Validates `.desktop` and AppStream `.metainfo.xml` files.
   - Builds the package using `flatpak/flatpak-github-actions/flatpak-builder@v6`.
   - Generates a downloadable `io.filen.desktop-x86_64.flatpak` artifact for testing.

2. **`release.yml` (Automated Releases):**
   - Triggers when a Git tag (e.g. `v3.0.53`) is pushed.
   - Builds the production Flatpak bundle.
   - Attaches `io.filen.desktop.flatpak` directly to the GitHub Release.

---

## Repository Structure

```
io.filen.desktop/
├── .github/
│   └── workflows/
│       ├── build.yml                 # Automated CI build & metadata validation
│       └── release.yml               # Automated release bundle publisher
├── icons/                            # Standard hicolor PNG icons (16x16 to 1024x1024)
│   ├── 16x16.png
│   ├── ...
│   └── 1024x1024.png
├── .gitignore                        # Build directory & artifact exclusions
├── filen-directories.conf            # Directory policy & sync path configuration
├── filen.sh                          # App launcher & sandbox supervisor wrapper
├── flathub.json                      # Flathub builder settings
├── io.filen.desktop.desktop          # XDG Desktop entry
├── io.filen.desktop.metainfo.xml      # AppStream metadata & release info
├── io.filen.desktop.yaml             # Main Flatpak build manifest
└── README.md                         # Documentation & build instructions
```

---

## Sandboxing & Architecture Details

* **Display Support:** Wayland native display with automatic fallback to X11/Xwayland.
* **Credentials:** Persistent authentication tokens via Freedesktop Secret Service (`org.freedesktop.secrets`) and KDE KWallet (`kwalletd5` / `kwalletd6`).
* **Tray & UI:** System tray and status icons integrated via D-Bus (`com.canonical.AppMenu.Registrar`, `com.canonical.Unity`).
* **Cloud Storage & rclone:** Includes bundled `rclone` (v1.74.3) with support for local WebDAV and S3 endpoints.
* **Update Policy:** Native in-app self-updating (`electron-updater`) is disabled within the Flatpak to preserve container immutability, deferring update lifecycle management to Flatpak.
