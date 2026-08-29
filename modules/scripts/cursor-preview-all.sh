#!/usr/bin/env bash
# Extracts a small preview PNG (closest to 32px) for every installed
# cursor theme's "left_ptr" cursor into a cache directory, one per theme
# named "<theme>.png". Xcursor files are a binary format QML's Image
# element can't decode directly, so this is a one-time render step —
# already-cached themes are skipped.
#
# usage: cursor-preview-all <cache-dir>
set -euo pipefail

cache_dir="${1:?usage: cursor-preview-all <cache-dir>}"
mkdir -p "$cache_dir"

dirs=(
    "$HOME/.icons"
    "$HOME/.local/share/icons"
    "/run/current-system/sw/share/icons"
    "/etc/profiles/per-user/$USER/share/icons"
)

render_one() {
    local theme="$1"
    local src="$2"
    local out="$cache_dir/$theme.png"
    [ -e "$out" ] && return 0

    local tmp
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' RETURN

    xcur2png -q -d "$tmp" -c "$tmp/conf" -i 1 "$src" > /dev/null 2>&1 || return 0

    local best=""
    local best_diff=999999
    for png in "$tmp"/*.png; do
        [ -e "$png" ] || continue
        local w
        w=$(identify -format "%w" "$png" 2>/dev/null || echo 0)
        local diff=$(( w > 32 ? w - 32 : 32 - w ))
        if [ "$diff" -lt "$best_diff" ]; then
            best_diff=$diff
            best="$png"
        fi
    done
    [ -n "$best" ] && cp "$best" "$out"
}

for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    for theme_dir in "$d"/*/; do
        [ -f "${theme_dir}cursors/left_ptr" ] || continue
        render_one "$(basename "$theme_dir")" "${theme_dir}cursors/left_ptr"
    done
done
