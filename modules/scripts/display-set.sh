#!/usr/bin/env bash
# Applies a full monitor descriptor immediately (hyprctl) AND persists it
# into ~/.config/hypr/display.conf, which hyprland.conf sources — without
# that file, hyprland.conf's generic fallback rule
# ("monitor = , preferred, auto, 1") is the only thing on record, and
# ANYTHING that makes Hyprland re-evaluate monitor state (observed: even
# changing the cursor theme via `hyprctl setcursor` does this) reapplies
# that fallback, silently dropping back to "preferred" refresh rate
# instead of whatever the user actually picked.
#
# Takes the monitor name and everything after it as one pre-built
# descriptor string (mode,position,scale + optional transform/bitdepth/
# cm/sdrbrightness/sdrsaturation/vrr/icc keyword,value pairs) rather than
# fixed positional args — Hyprland's own `monitor` keyword syntax grew
# past "mode/x/y/scale/transform" (color management, HDR, VRR, ICC), and
# the caller (LeftFlyout.qml's Displays panel) already has all of that as
# structured state, so it's simpler for it to build the one string than
# for this script to accept a growing positional argument list.
set -euo pipefail

mon="${1:?usage: display-set <monitor> <descriptor-tail>}"
descriptor_tail="${2:?descriptor required}"

descriptor="$mon,$descriptor_tail"

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
