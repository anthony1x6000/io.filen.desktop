# Filen desktop Flatpak (`io.filen.desktop`)

**Warning**: This is an unofficial Flatpak build of Filen, generated from the official Filen-built `.deb` packages here: https://filen.io/products/desktop

Flatpak packaging for the Filen desktop client (`io.filen.desktop`).

## Installation

### Install from repo

With repo, you get automatic updates. [CI](https://github.com/anthony1x6000/io.filen.desktop/blob/main/scripts/actions/auto-update.sh) is made to automatically package a new Filen release upstream. 

Ensure Flathub and the Filen repository are added:

```bash
# Add Flathub for runtime dependencies
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Add Filen repository
flatpak remote-add --if-not-exists --user filen https://anthony1x6000.github.io/io.filen.desktop/io.filen.desktop.flatpakrepo
```

Install:

```bash
flatpak install --user filen io.filen.desktop
```

Or install in a single command via `.flatpakref`:

```bash
flatpak install --user https://anthony1x6000.github.io/io.filen.desktop/io.filen.desktop.flatpakref
```

And update like usual:

```bash
flatpak update
```

### Install the .flatpak, no repo

```bash
flatpak install --user https://github.com/anthony1x6000/io.filen.desktop/releases/latest/download/io.filen.desktop.flatpak
```

## Run the app

```bash
flatpak run io.filen.desktop
```

## Default permissionss

- `~/Downloads`
- `~/.var/app/io.filen.desktop/`

If you want more directories, use [Flatseal](https://flathub.org/en/apps/com.github.tchx84.Flatseal) and add new directories. 

You can also use CLI: 
```bash
flatpak override --user --filesystem=~/Documents io.filen.desktop
```

# AI use and credit
- Google antigravity was used to create this project. 
  - Scripts used are kept inside of [scripts/](https://github.com/anthony1x6000/io.filen.desktop/tree/main/scripts), so you can audit the code for yourself.
- Based off https://github.com/flathub/com.visualstudio.code.
