#!/bin/bash
# Load-aware fan control for MSI laptops using the msi-ec driver.
# Profile is read from $PROFILE_FILE every cycle (set it with `fanprofile <name>`):
#   auto     - 3 levels by temperature: comfort -> turbo -> turbo + cooler_boost
#   quiet    - eco, fans auto, no boost
#   balanced - comfort, fans auto, no boost
#   max      - turbo + cooler_boost on, always
# State is re-asserted every cycle, so resets after suspend/resume are fixed automatically.

EC=/sys/devices/platform/msi-ec
PROFILE_FILE=/var/lib/msi-fancontrol/profile

# Tunables for "auto" (override in /etc/default/msi-fancontrol)
# Three levels: 0 = comfort, 1 = turbo with firmware-controlled fans, 2 = turbo + cooler_boost (max fans)
# Level 1 (turbo, fans still follow the firmware curve):
CPU_HOT=${CPU_HOT:-80};   GPU_HOT=${GPU_HOT:-72}     # step up to 1 when CPU or GPU >= this
CPU_COOL=${CPU_COOL:-68}; GPU_COOL=${GPU_COOL:-60}   # step down to 0 when both < this
HOT_SECS=${HOT_SECS:-15}                             # must be hot this long before stepping up
COOL_SECS=${COOL_SECS:-60}                           # must be cool this long before stepping down
# Level 2 (cooler_boost, fans at 100%) - only for sustained heavy load:
CPU_MAX=${CPU_MAX:-92};   GPU_MAX=${GPU_MAX:-80}     # step up to 2 when CPU or GPU >= this
CPU_MAXCOOL=${CPU_MAXCOOL:-86}; GPU_MAXCOOL=${GPU_MAXCOOL:-74}  # step down to 1 when both < this
MAX_SECS=${MAX_SECS:-30}                             # must be this hot before max fans
MAXCOOL_SECS=${MAXCOOL_SECS:-30}                     # must be below MAXCOOL this long to leave max fans
INTERVAL=${INTERVAL:-2}
DRY_RUN=${DRY_RUN:-0}
[ -r /etc/default/msi-fancontrol ] && . /etc/default/msi-fancontrol

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

level=0; up_t=0; down_t=0; last_profile=
# Keep an already-active boost on at startup (avoids a noisy off/on flap on restart)
[ "$(cat $EC/cooler_boost 2>/dev/null)" = on ] && level=2
trap 'apply comfort off; exit 0' TERM INT

while true; do
    if [ ! -r "$EC/cpu/realtime_temperature" ]; then sleep 5; continue; fi
    profile=$(cat "$PROFILE_FILE" 2>/dev/null); profile=${profile:-auto}
    [ "$profile" != "$last_profile" ] && { log "profile: ${last_profile:-start} -> $profile"; last_profile=$profile; }

    case "$profile" in
        quiet)    apply eco off;     level=0 ;;
        balanced) apply comfort off; level=0 ;;
        max)      apply turbo on;    level=2 ;;
        *)
            cpu=$(cat "$EC/cpu/realtime_temperature"); gpu=$(cat "$EC/gpu/realtime_temperature")
            # thresholds for stepping up out of / down from the current level
            case "$level" in
                0) uc=$CPU_HOT; ug=$GPU_HOT; us=$HOT_SECS;  dc=0; dg=0; ds=0 ;;
                1) uc=$CPU_MAX; ug=$GPU_MAX; us=$MAX_SECS;  dc=$CPU_COOL; dg=$GPU_COOL; ds=$COOL_SECS ;;
                2) uc=999;      ug=999;      us=1;          dc=$CPU_MAXCOOL; dg=$GPU_MAXCOOL; ds=$MAXCOOL_SECS ;;
            esac
            if [ "$cpu" -ge "$uc" ] || [ "$gpu" -ge "$ug" ]; then
                up_t=$((up_t + INTERVAL)); down_t=0
                if [ "$up_t" -ge "$us" ]; then level=$((level + 1)); up_t=0; log "level -> $level (cpu=$cpu gpu=$gpu)"; fi
            elif [ "$cpu" -lt "$dc" ] && [ "$gpu" -lt "$dg" ]; then
                down_t=$((down_t + INTERVAL)); up_t=0
                if [ "$down_t" -ge "$ds" ]; then level=$((level - 1)); down_t=0; log "level -> $level (cpu=$cpu gpu=$gpu)"; fi
            else up_t=0; down_t=0; fi
            case "$level" in
                0) apply comfort off ;;
                1) apply turbo off ;;
                2) apply turbo on ;;
            esac
            ;;
    esac
    sleep "$INTERVAL"
done
