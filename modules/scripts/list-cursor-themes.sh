#!/usr/bin/env bash
# Lists installed Xcursor themes by scanning the real XCURSOR_PATH locations
# for a "cursors" subdirectory — no hardcoded theme names.
set -euo pipefail

dirs=(
    "$HOME/.icons"
    "$HOME/.local/share/icons"
    "/run/current-system/sw/share/icons"
    # Packages installed via users.users.<name>.packages (as opposed to
    # environment.systemPackages) land here, not under
    # /run/current-system/sw — this is where bibata-cursors actually is.
    "/etc/profiles/per-user/$USER/share/icons"
)

for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    for theme in "$d"/*/; do
        [ -d "${theme}cursors" ] || continue
        basename "$theme"
    done
done | sort -u
