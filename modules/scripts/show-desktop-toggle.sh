#!/usr/bin/env bash
# "Show desktop" for Hyprland: stashes every window on the active workspace
# into a hidden special workspace, and restores each one to the workspace
# it came from on the next press — regardless of which workspace you're on
# when you press it again (a single global state file, not one keyed by
# "current workspace", which broke the moment you switched workspaces
# in between).
set -euo pipefail

state_file="${XDG_RUNTIME_DIR:-/tmp}/hypr-show-desktop.json"

if [ -s "$state_file" ]; then
    jq -c '.[]' "$state_file" | while IFS= read -r entry; do
        addr=$(echo "$entry" | jq -r '.address')
        ws=$(echo "$entry" | jq -r '.workspace')
        hyprctl dispatch movetoworkspacesilent "$ws,address:$addr" > /dev/null
    done
    rm -f "$state_file"
else
    ws_id=$(hyprctl activeworkspace -j | jq -r '.id')
    hyprctl clients -j | jq -c --argjson ws "$ws_id" \
        '[.[] | select(.workspace.id == $ws) | {address: .address, workspace: $ws}]' > "$state_file"
    jq -r '.[].address' "$state_file" | while IFS= read -r addr; do
        [ -n "$addr" ] && hyprctl dispatch movetoworkspacesilent "special:showdesktop,address:$addr" > /dev/null
    done
fi
