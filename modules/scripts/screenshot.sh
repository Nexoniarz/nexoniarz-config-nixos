#!/usr/bin/env bash
# Unified screenshot helper.
#   screenshot <region|full|window> <clipboard|file|both>
set -euo pipefail

mode="${1:-region}"
action="${2:-both}"

geom=()
case "$mode" in
    region)
        sel="$(slurp)" || exit 0
        [ -z "$sel" ] && exit 0
        geom=(-g "$sel")
        ;;
    window)
        win="$(hyprctl activewindow -j)"
        at_x=$(echo "$win" | jq -r '.at[0]')
        at_y=$(echo "$win" | jq -r '.at[1]')
        w=$(echo "$win" | jq -r '.size[0]')
        h=$(echo "$win" | jq -r '.size[1]')
        geom=(-g "${at_x},${at_y} ${w}x${h}")
        ;;
    full)
        geom=()
        ;;
    *)
        echo "unknown mode: $mode (expected region|full|window)" >&2
        exit 1
        ;;
esac

mkdir -p "$HOME/Screenshots"
file="$HOME/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png"

case "$action" in
    clipboard)
        grim "${geom[@]}" - | wl-copy
        ;;
    file)
        grim "${geom[@]}" "$file"
        ;;
    both)
        grim "${geom[@]}" "$file"
        wl-copy < "$file"
        ;;
    *)
        echo "unknown action: $action (expected clipboard|file|both)" >&2
        exit 1
        ;;
esac
