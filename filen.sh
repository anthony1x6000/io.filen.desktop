#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 Filen Flatpak Packaging Contributors
set -e

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/filen"
USER_CONFIG="${CONFIG_DIR}/directories.conf"
SYS_CONFIG="/app/etc/filen-directories.conf"

log() {
    echo "[flatpak-filen] $*" >&2
}

# 1. Initialize user configuration directory and default config if missing
if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
fi

if [ ! -f "$USER_CONFIG" ] && [ -f "$SYS_CONFIG" ]; then
    log "Creating default user directory configuration at $USER_CONFIG"
    cp "$SYS_CONFIG" "$USER_CONFIG"
fi

# 2. Source system defaults followed by user overrides
if [ -f "$SYS_CONFIG" ]; then
    # shellcheck source=/dev/null
    source "$SYS_CONFIG"
fi

if [ -f "$USER_CONFIG" ]; then
    # shellcheck source=/dev/null
    source "$USER_CONFIG"
fi

# 3. Expand and prepare configured directories
if [ -n "$FILEN_SYNC_ROOT" ]; then
    EXPANDED_SYNC_ROOT=$(eval echo "$FILEN_SYNC_ROOT")
    if [ "$FILEN_AUTO_CREATE_SYNC_ROOT" = "true" ] && [ ! -d "$EXPANDED_SYNC_ROOT" ]; then
        log "Ensuring sync root directory exists: $EXPANDED_SYNC_ROOT"
        mkdir -p "$EXPANDED_SYNC_ROOT" 2>/dev/null || {
            log "WARNING: Could not create sync root $EXPANDED_SYNC_ROOT. Verify filesystem permissions."
            log "Hint: Run 'flatpak override --user --filesystem=$EXPANDED_SYNC_ROOT io.filen.desktop' if on an external drive."
        }
    fi
fi

# 4. Check permitted directories accessibility
if [ -n "$FILEN_ALLOWED_DIRS" ]; then
    IFS=':' read -ra DIRS <<< "$FILEN_ALLOWED_DIRS"
    for DIR in "${DIRS[@]}"; do
        EXP_DIR=$(eval echo "$DIR")
        if [ ! -d "$EXP_DIR" ] && [ "$FILEN_STRICT_DIRECTORY_CHECK" = "true" ]; then
            log "Notice: Configured allowed directory $EXP_DIR is not present or accessible."
        fi
    done
fi

# 5. Wayland and display platform parameters
EXTRA_ARGS=()
if [ "$XDG_SESSION_TYPE" = "wayland" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    EXTRA_ARGS+=(
        "--ozone-platform-hint=auto"
        "--enable-features=WaylandWindowDecorations"
    )
fi

# 6. Disable in-app self-updater (Flatpak handles updates via package manager)
export ELECTRON_DISABLE_UPDATER=1
export ELECTRON_TRASH=gio
export XCURSOR_PATH=/run/host/user-share/icons:/run/host/share/icons

# 7. Execute application via Zypak sandbox supervisor
EXECUTABLE="/app/main/Filen"
if [ ! -f "$EXECUTABLE" ]; then
    # Fallback search path in case of alternate distribution packaging
    for candidate in /app/main/filen /app/extra/Filen /app/extra/filen; do
        if [ -f "$candidate" ]; then
            EXECUTABLE="$candidate"
            break
        fi
    done
fi

exec zypak-wrapper "$EXECUTABLE" "${EXTRA_ARGS[@]}" "$@"
