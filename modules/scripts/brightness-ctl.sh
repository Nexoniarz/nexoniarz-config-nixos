#!/usr/bin/env bash
# Brightness control abstraction: prefers the kernel backlight class (laptop
# panels, via brightnessctl); falls back to DDC/CI over I2C (external
# monitors, via ddcutil) when no backlight device exists. Keeps the rest of
# the config (Quickshell's brightness popup) hardware-agnostic.
set -euo pipefail

has_backlight() {
    [ -n "$(ls -A /sys/class/backlight 2>/dev/null)" ]
}

case "${1:-get}" in
    get)
        if has_backlight; then
            brightnessctl -m | cut -d, -f4 | tr -d '%'
        else
            ddcutil getvcp 10 --brief 2>/dev/null | awk '{print $4}'
        fi
        ;;
    set)
        pct="${2:?usage: brightness-ctl set <0-100>}"
        if has_backlight; then
            brightnessctl set "${pct}%" > /dev/null
        else
            ddcutil setvcp 10 "$pct" > /dev/null
        fi
        ;;
    *)
        echo "usage: brightness-ctl [get|set <0-100>]" >&2
        exit 1
        ;;
esac
