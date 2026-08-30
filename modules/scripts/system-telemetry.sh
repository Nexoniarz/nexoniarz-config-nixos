#!/usr/bin/env bash
# Single-shot system telemetry snapshot — CPU/RAM/GPU/VRAM/disk usage — as
# one JSON object, so the Quickshell System panel can poll this on a Timer
# instead of spawning half a dozen separate processes every tick.
set -euo pipefail

# --- CPU ---
# /proc/stat's first line ("cpu ...") is cumulative jiffies since boot —
# computing instantaneous usage needs two samples across a short gap, so
# both reads happen inside this one invocation rather than needing
# cross-poll state kept on the QML side.
read_cpu() {
    read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
    echo "$((user + nice + system + irq + softirq + steal)) $((user + nice + system + idle + iowait + irq + softirq + steal))"
}
read -r cpu_busy1 cpu_total1 <<< "$(read_cpu)"
sleep 0.2
read -r cpu_busy2 cpu_total2 <<< "$(read_cpu)"
cpu_busy_delta=$((cpu_busy2 - cpu_busy1))
cpu_total_delta=$((cpu_total2 - cpu_total1))
cpu_pct=0
[ "$cpu_total_delta" -gt 0 ] && cpu_pct=$((100 * cpu_busy_delta / cpu_total_delta))

# --- RAM ---
mem_total_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
mem_avail_kb=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
mem_used_kb=$((mem_total_kb - mem_avail_kb))

# --- GPU / VRAM ---
# NVIDIA checked first via nvidia-smi (works regardless of which DRM card
# index the driver landed on); AMD falls back to the card0 sysfs counters
# directly — whichever's actually present decides which branch fires, so
# this works unmodified on either machine.
gpu_pct=-1
vram_used_mb=-1
vram_total_mb=-1
if command -v nvidia-smi > /dev/null 2>&1 && nvidia-smi -L > /dev/null 2>&1; then
    nv_out="$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits -i 0 2>/dev/null | tr -d ' ')"
    IFS=',' read -r gpu_pct vram_used_mb vram_total_mb <<< "$nv_out"
elif [ -e /sys/class/drm/card0/device/gpu_busy_percent ]; then
    gpu_pct="$(cat /sys/class/drm/card0/device/gpu_busy_percent 2>/dev/null || echo -1)"
    if [ -e /sys/class/drm/card0/device/mem_info_vram_used ]; then
        vram_used_mb=$(($(cat /sys/class/drm/card0/device/mem_info_vram_used) / 1024 / 1024))
        vram_total_mb=$(($(cat /sys/class/drm/card0/device/mem_info_vram_total) / 1024 / 1024))
    fi
fi

# --- Disks (root + home) ---
# Positional ($NF for mountpoint), not header-text matching — `df -h`'s
# header is locale-translated (verified live: "System plików"/"%uż." under
# this machine's pl_PL locale, not "Filesystem"/"Use%"), so matching on
# English header text would silently find nothing.
disks_json="$(df -h 2>/dev/null | awk '
    NR == 1 { next }
    $NF == "/" || $NF == "/home" {
        gsub(/%/, "", $5)
        printf "%s{\"mount\":\"%s\",\"size\":\"%s\",\"used\":\"%s\",\"avail\":\"%s\",\"pct\":\"%s\"}", (n++ ? "," : ""), $NF, $2, $3, $4, $5
    }
')"

printf '{"cpuPct":%s,"memUsedKb":%s,"memTotalKb":%s,"gpuPct":%s,"vramUsedMb":%s,"vramTotalMb":%s,"disks":[%s]}\n' \
    "$cpu_pct" "$mem_used_kb" "$mem_total_kb" "$gpu_pct" "$vram_used_mb" "$vram_total_mb" "$disks_json"
