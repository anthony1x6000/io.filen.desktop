#!/bin/bash
set -euo pipefail

# Wayland display platform parameters
EXTRA_ARGS=()
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    EXTRA_ARGS+=(
        "--ozone-platform-hint=auto"
        "--enable-features=WaylandWindowDecorations"
    )
fi

# Environment configuration
unset GTK_MODULES
export ELECTRON_DISABLE_UPDATER=1
export ELECTRON_TRASH=gio
export XCURSOR_PATH=/run/host/user-share/icons:/run/host/share/icons

exec zypak-wrapper /app/main/Filen "${EXTRA_ARGS[@]}" "$@"
