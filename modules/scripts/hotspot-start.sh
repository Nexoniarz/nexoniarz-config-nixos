#!/usr/bin/env bash
# Starts a Wi-Fi hotspot with explicit security/band control — the simple
# `nmcli device wifi hotspot` one-liner doesn't expose those.
#   hotspot-start <ssid> <password> <wpa2|wpa3> <auto|bg|a>
set -euo pipefail

ssid="${1:?usage: hotspot-start <ssid> <password> <wpa2|wpa3> <auto|bg|a>}"
password="${2:?password required}"
security="${3:-wpa2}"
band="${4:-auto}"

iface=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}')
if [ -z "$iface" ]; then
    echo "No Wi-Fi device found" >&2
    exit 1
fi

# Idempotent: drop any previous Hotspot profile from an earlier run first.
nmcli connection delete Hotspot >/dev/null 2>&1 || true

key_mgmt="wpa-psk"
[ "$security" = "wpa3" ] && key_mgmt="sae"

nmcli connection add type wifi ifname "$iface" con-name Hotspot autoconnect no ssid "$ssid" > /dev/null
nmcli connection modify Hotspot 802-11-wireless.mode ap
if [ "$band" != "auto" ]; then
    nmcli connection modify Hotspot 802-11-wireless.band "$band"
fi
nmcli connection modify Hotspot wifi-sec.key-mgmt "$key_mgmt"
nmcli connection modify Hotspot wifi-sec.psk "$password"
nmcli connection modify Hotspot ipv4.method shared

nmcli connection up Hotspot
