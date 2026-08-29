#!/usr/bin/env bash
# Regenerates ~/.config/kitty/theme.conf (included from kitty.conf) to
# match the current Quickshell theme. No explicit reload needed — kitty
# has a built-in config-file watcher (visible as `kitten __watch_conf__`
# in its process list) that also watches included files, so this takes
# effect live in already-open kitty windows.
set -euo pipefail

accent="${1:?usage: kitty-theme-set <accent> <bg> <bgAlt> <fg> <fgDim> <border>}"
bg="${2:?bg required}"
bg_alt="${3:?bgAlt required}"
fg="${4:?fg required}"
fg_dim="${5:?fgDim required}"
border="${6:?border required}"

conf="$HOME/.config/kitty/theme.conf"
mkdir -p "$(dirname "$conf")"

cat > "$conf" <<EOF
background               $bg
foreground                $fg
selection_background      $border
selection_foreground      $fg
cursor                    $fg
active_border_color       $accent
inactive_border_color     $border
active_tab_background     $bg_alt
active_tab_foreground     $fg
inactive_tab_background   $bg
inactive_tab_foreground   $fg_dim
EOF
