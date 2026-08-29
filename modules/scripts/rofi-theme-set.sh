#!/usr/bin/env bash
# Regenerates ~/.config/rofi/theme.rasi (imported by config.rasi) to match
# the current Quickshell theme. Rofi has no config-file watcher — unlike
# kitty, it's launched on demand rather than staying resident, so the next
# time it's opened it just reads whatever is on disk. No reload step needed.
set -euo pipefail

accent="${1:?usage: rofi-theme-set <accent> <bg> <bgAlt> <fg> <fgDim> <border> <dark:1|0>}"
bg="${2:?bg required}"
bg_alt="${3:?bgAlt required}"
fg="${4:?fg required}"
fg_dim="${5:?fgDim required}"
border="${6:?border required}"
dark="${7:?dark required}"

icon_theme="Gruvbox-Plus-Light"
if [ "$dark" = "1" ]; then
    icon_theme="Gruvbox-Plus-Dark"
fi

conf="$HOME/.config/rofi/theme.rasi"
mkdir -p "$(dirname "$conf")"

cat > "$conf" <<EOF
* {
    bg:            ${bg}ee;
    bg-alt:        ${bg_alt}ee;
    fg:            ${fg}ff;
    accent:        ${accent}ff;
    border-color:  ${border}ff;
    placeholder:   ${fg_dim}ff;
}
configuration {
    icon-theme: "$icon_theme";
}
EOF
