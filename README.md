# Filen desktop Flatpak (`io.filen.desktop`)

**Warning**: This is an unofficial Flatpak build of Filen, generated from the official Filen-built `.deb` packages here: https://filen.io/products/desktop

Flatpak packaging for the Filen desktop client (`io.filen.desktop`).

## Installation

### Option 1: Install from the Flatpak repository (automatic updates)

Add the repository:

```bash
flatpak remote-add --if-not-exists --user filen https://anthony1x6000.github.io/io.filen.desktop/io.filen.desktop.flatpakrepo
```

Install Filen Desktop:

```bash
flatpak install --user filen io.filen.desktop
```

Update at any time with your regular Flatpak updates:

```bash
flatpak update
```

### Option 2: Install from standalone `.flatpak` bundle

Download the latest `io.filen.desktop.flatpak` bundle from [GitHub Releases](https://github.com/anthony1x6000/io.filen.desktop/releases) and install:

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

## Default sandbox permissions and Flatseal

By default, the Flatpak sandbox is strictly isolated with minimal filesystem privileges:

* **Filesystem access:** Restricted strictly to `~/Downloads` (`xdg-download`).
* **Application data:** Stored securely inside `~/.var/app/io.filen.desktop/`.

### Granting access to additional directories

If you want to sync folders outside of `~/Downloads` (such as `~/Documents`, `~/Projects`, or external drives):

1. **Using Flatseal (graphical interface):**
   * Open **Flatseal** and select **Filen**.
   * Scroll down to the **Filesystem** section -> **Other files**.
   * Click **+** (Add) and enter your desired directory path (e.g. `~/Documents` or `/media/storage`).

2. **Using the command line:**
   ```bash
   flatpak override --user --filesystem=~/Documents io.filen.desktop
   flatpak override --user --filesystem=/media/storage io.filen.desktop
   ```

## License

Licensed under the [GNU Affero General Public License v3.0](LICENSE) (`AGPL-3.0-only`).
