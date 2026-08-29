#!/usr/bin/env bash
# Applies a cursor theme immediately (hyprctl) and persists it across
# restarts by writing env vars to a file hyprland.conf sources on startup.
set -euo pipefail

theme="${1:?usage: cursor-set <theme-name> [size]}"
size="${2:-24}"

hyprctl setcursor "$theme" "$size" > /dev/null

mkdir -p "$HOME/.config/hypr"
cat > "$HOME/.config/hypr/cursor.conf" <<EOF
env = HYPRCURSOR_THEME,$theme
env = XCURSOR_THEME,$theme
env = XCURSOR_SIZE,$size
EOF
