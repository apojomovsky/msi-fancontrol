#!/bin/bash
# Load-aware fan control for MSI laptops using the msi-ec driver.
# Profile is read from $PROFILE_FILE every cycle (set it with `fanprofile <name>`):
#   auto     - hot: turbo + cooler_boost on; cool: comfort + cooler_boost off
#   quiet    - eco, fans auto, no boost
#   balanced - comfort, fans auto, no boost
#   max      - turbo + cooler_boost on, always
# State is re-asserted every cycle, so resets after suspend/resume are fixed automatically.

EC=/sys/devices/platform/msi-ec
PROFILE_FILE=/var/lib/fan-boost/profile

# Tunables for "auto" (override in /etc/default/fan-boost)
CPU_HOT=${CPU_HOT:-85}      # boost when CPU >= this (°C)
GPU_HOT=${GPU_HOT:-75}      # ...or GPU >= this
CPU_COOL=${CPU_COOL:-70}    # un-boost only when CPU < this
GPU_COOL=${GPU_COOL:-62}    # ...and GPU < this
HOT_SECS=${HOT_SECS:-10}    # must be hot this long before boosting
COOL_SECS=${COOL_SECS:-60}  # must be cool this long before un-boosting
INTERVAL=${INTERVAL:-2}
DRY_RUN=${DRY_RUN:-0}
[ -r /etc/default/fan-boost ] && . /etc/default/fan-boost

log() { echo "$*"; }

set_attr() {  # name value
    local cur; cur=$(cat "$EC/$1" 2>/dev/null)
    [ "$cur" = "$2" ] && return
    if [ "$DRY_RUN" = 1 ]; then log "[dry-run] $1: $cur -> $2"; else
        echo "$2" > "$EC/$1" && log "$1: $cur -> $2"
    fi
}

apply() {  # shift_mode cooler_boost
    set_attr fan_mode auto
    if [ "$2" = on ]; then set_attr shift_mode "$1"; set_attr cooler_boost on
    else set_attr cooler_boost off; set_attr shift_mode "$1"; fi
}

boosted=0; hot_t=0; cool_t=0; last_profile=
# Keep an already-active boost on at startup (avoids a noisy off/on flap on restart)
[ "$(cat $EC/cooler_boost 2>/dev/null)" = on ] && boosted=1
trap 'apply comfort off; exit 0' TERM INT

while true; do
    if [ ! -r "$EC/cpu/realtime_temperature" ]; then sleep 5; continue; fi
    profile=$(cat "$PROFILE_FILE" 2>/dev/null); profile=${profile:-auto}
    [ "$profile" != "$last_profile" ] && { log "profile: ${last_profile:-start} -> $profile"; last_profile=$profile; }

    case "$profile" in
        quiet)    apply eco off;     boosted=0 ;;
        balanced) apply comfort off; boosted=0 ;;
        max)      apply turbo on;    boosted=1 ;;
        *)
            cpu=$(cat "$EC/cpu/realtime_temperature"); gpu=$(cat "$EC/gpu/realtime_temperature")
            if [ "$boosted" = 0 ]; then
                if [ "$cpu" -ge "$CPU_HOT" ] || [ "$gpu" -ge "$GPU_HOT" ]; then
                    hot_t=$((hot_t + INTERVAL))
                    if [ "$hot_t" -ge "$HOT_SECS" ]; then boosted=1; cool_t=0; log "BOOST on (cpu=$cpu gpu=$gpu)"; fi
                else hot_t=0; fi
            else
                if [ "$cpu" -lt "$CPU_COOL" ] && [ "$gpu" -lt "$GPU_COOL" ]; then
                    cool_t=$((cool_t + INTERVAL))
                    if [ "$cool_t" -ge "$COOL_SECS" ]; then boosted=0; hot_t=0; log "BOOST off (cpu=$cpu gpu=$gpu)"; fi
                else cool_t=0; fi
            fi
            if [ "$boosted" = 1 ]; then apply turbo on; else apply comfort off; fi
            ;;
    esac
    sleep "$INTERVAL"
done
