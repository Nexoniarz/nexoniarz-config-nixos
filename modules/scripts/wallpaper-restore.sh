#!/usr/bin/env bash
# Reapplies the last-set wallpaper on login/reboot. hyprpaper and mpvpaper
# both start every session with nothing loaded, and wallpaper-set only ever
# ran through live IPC with no persistence of its own — without this the
# desktop silently reverted to blank on every fresh login. Run via
# exec-once in hyprland.conf, after hyprpaper.
set -euo pipefail

state_file="$HOME/.config/hypr/wallpaper.conf"
[ -f "$state_file" ] || exit 0

# hyprpaper's IPC socket isn't guaranteed ready the instant exec-once fires
# it, since exec-once entries all start back-to-back with no ordering
# guarantee beyond process spawn order.
for _ in $(seq 1 50); do
    hyprctl hyprpaper listactive > /dev/null 2>&1 && break
    sleep 0.1
done

bash "$state_file"
