#!/usr/bin/env bash
# Applies a monitor mode/position/scale/transform immediately (hyprctl)
# AND persists it into ~/.config/hypr/display.conf, which hyprland.conf
# sources — without that file, hyprland.conf's generic fallback rule
# ("monitor = , preferred, auto, 1") is the only thing on record, and
# ANYTHING that makes Hyprland re-evaluate monitor state (observed: even
# changing the cursor theme via `hyprctl setcursor` does this) reapplies
# that fallback, silently dropping back to "preferred" refresh rate
# instead of whatever the user actually picked.
set -euo pipefail

mon="${1:?usage: display-set <monitor> <mode> <x> <y> <scale> [transform]}"
mode="${2:?mode required}"
x="${3:?x required}"
y="${4:?y required}"
scale="${5:?scale required}"
transform="${6:-0}"

descriptor="$mon,$mode,${x}x${y},$scale"
[ "$transform" != "0" ] && descriptor="$descriptor,transform,$transform"

conf="$HOME/.config/hypr/display.conf"
mkdir -p "$(dirname "$conf")"
touch "$conf"

line="monitor = $descriptor"
if grep -q "^monitor = $mon," "$conf" 2>/dev/null; then
    # mktemp in the same directory as $conf, not the default /tmp: /tmp is
    # a different filesystem here, which makes `mv` below a non-atomic
    # copy+unlink instead of a rename — Hyprland's file watcher (it
    # watches every `source=`d file, including this one) could catch the
    # destination mid-replace and its `source=` glob would find nothing,
    # throwing "globbing error: found no match" (observed live after an
    # orientation change, which always hits this branch since DP-1
    # already has an existing line by then).
    tmp=$(mktemp "$conf.XXXXXX")
    awk -v prefix="monitor = $mon," -v newline="$line" '
        index($0, prefix) == 1 { print newline; next } { print }
    ' "$conf" > "$tmp"
    mv "$tmp" "$conf"
else
    echo "$line" >> "$conf"
fi

hyprctl keyword monitor "$descriptor" > /dev/null
