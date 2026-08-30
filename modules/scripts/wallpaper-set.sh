#!/usr/bin/env bash
# Sets the desktop wallpaper — static images go through hyprpaper's IPC,
# video files loop via mpvpaper. Only one backend should ever be driving
# the background at a time, so switching to one always tears the other
# down first.
#
# usage: wallpaper-set <path> [fit_mode] [muted] [speed] [auto_pause]
#   fit_mode:   cover|contain   (static images only, default cover)
#   muted:      1|0             (animated only, default 1)
#   speed:      playback speed  (animated only, default 1.0)
#   auto_pause: 1|0             (animated only — mpvpaper -p, pauses
#                                 playback while the wallpaper is hidden
#                                 behind a fullscreen window, default 1)
set -euo pipefail

image="${1:?usage: wallpaper-set <path> [fit_mode] [muted] [speed] [auto_pause]}"
fit_mode="${2:-cover}"
muted="${3:-1}"
speed="${4:-1.0}"
auto_pause="${5:-1}"

case "${image,,}" in
    *.mp4|*.webm|*.mkv|*.mov|*.gif)
        # -9: plain SIGTERM doesn't reliably kill mpvpaper (verified live —
        # it survives pkill -f without -9), which would leave the old
        # instance still holding the layer-shell surface underneath a new
        # one. The short sleep gives it a moment to actually release that
        # surface before a replacement tries to claim it.
        pkill -9 -f mpvpaper > /dev/null 2>&1 || true
        sleep 0.3

        mpv_opts="loop-playlist=inf speed=$speed"
        [ "$muted" = "1" ] && mpv_opts="no-audio $mpv_opts"

        mpvpaper_flags=()
        [ "$auto_pause" = "1" ] && mpvpaper_flags+=("-p")

        # setsid + disown so mpvpaper (which runs forever, looping the
        # video) survives after this script exits.
        setsid mpvpaper "${mpvpaper_flags[@]}" -o "$mpv_opts" '*' "$image" \
            > /dev/null 2>&1 < /dev/null &
        disown
        ;;
    *)
        # -9: plain SIGTERM doesn't reliably kill mpvpaper (verified live —
        # it survives pkill -f without -9), which would leave the old
        # instance still holding the layer-shell surface underneath a new
        # one. The short sleep gives it a moment to actually release that
        # surface before a replacement tries to claim it.
        pkill -9 -f mpvpaper > /dev/null 2>&1 || true
        sleep 0.3
        # This hyprpaper version's IPC only exposes a single `wallpaper`
        # request (confirmed via `hyprctl hyprpaper --help`) — it loads
        # and swaps the image in one call. preload/unload/listloaded
        # requests it used to need don't exist anymore and error out with
        # "invalid hyprpaper request", which — combined with `set -e` —
        # was aborting this script before it ever got here.
        hyprctl hyprpaper wallpaper ",$image,$fit_mode" > /dev/null
        ;;
esac

# Persist so the wallpaper survives a reboot/relogin. hyprpaper/mpvpaper
# both start every session with nothing loaded — this was previously only
# ever set at runtime via IPC, so the desktop silently reverted to blank
# every fresh login. wallpaper-restore (exec-once in hyprland.conf, after
# hyprpaper starts) re-runs the exact command saved here.
state_file="$HOME/.config/hypr/wallpaper.conf"
mkdir -p "$(dirname "$state_file")"
printf 'wallpaper-set %q %q %q %q %q\n' "$image" "$fit_mode" "$muted" "$speed" "$auto_pause" > "$state_file"
