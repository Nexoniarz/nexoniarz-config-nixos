#!/usr/bin/env bash
# Generates (or reuses) a cached preview JPEG for each animated wallpaper
# — first frame ~1s in, to skip a common black/fade intro on most clips —
# so the Wallpapers panel can show a real thumbnail instead of a generic
# play icon. Prints "<source path>\t<thumbnail path>" per file on stdout
# once it's ready, so the caller (LeftFlyout.qml) never has to
# independently reconstruct the cache filename — it's a hash of the
# source path, chosen only to keep filenames short/safe, not something
# QML needs to know how to derive.
set -euo pipefail

cache_dir="${1:?usage: wallpaper-thumbs <cache-dir> <file...>}"
shift
mkdir -p "$cache_dir"

for file in "$@"; do
    [ -f "$file" ] || continue
    name="$(printf '%s' "$file" | sha1sum | cut -d' ' -f1)"
    thumb="$cache_dir/$name.jpg"
    if [ ! -f "$thumb" ] || [ "$file" -nt "$thumb" ]; then
        ffmpeg -y -ss 00:00:01 -i "$file" -frames:v 1 -vf "scale=320:-1" "$thumb" \
            > /dev/null 2>&1 || true
    fi
    [ -f "$thumb" ] && printf '%s\t%s\n' "$file" "$thumb"
done
