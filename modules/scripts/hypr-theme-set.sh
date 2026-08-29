#!/usr/bin/env bash
# Applies Hyprland's active/inactive window border colors immediately AND
# persists them into ~/.config/hypr/display.conf's sibling, theme.conf
# (sourced by hyprland.conf after the static general{} block, so it
# overrides those hardcoded defaults) — without that file, a config
# reload/restart would silently revert to whatever's hardcoded in
# hyprland.conf, same class of bug as the display-settings one.
set -euo pipefail

accent="${1:?usage: hypr-theme-set <accent_hex_no_hash> <border_hex_no_hash>}"
border="${2:?border required}"

hyprctl keyword general:col.active_border "rgba(${accent}ff)" > /dev/null
hyprctl keyword general:col.inactive_border "rgba(${border}ff)" > /dev/null

conf="$HOME/.config/hypr/theme.conf"
mkdir -p "$(dirname "$conf")"
cat > "$conf" <<EOF
general {
    col.active_border = rgba(${accent}ff)
    col.inactive_border = rgba(${border}ff)
}
EOF
