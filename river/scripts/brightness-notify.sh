#!/bin/sh
set -eu

case "${1:-}" in
    up) step='1%+' ;;
    down) step='1%-' ;;
    *) printf 'Usage: %s up|down\n' "$0" >&2; exit 2 ;;
esac

brightness=$(brightnessctl --class=backlight --machine-readable set "$step")
percent=$(printf '%s\n' "$brightness" | awk -F, 'NR == 1 { gsub(/%/, "", $4); print $4 }')

if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "brightness" -t 1500 \
        -h string:x-canonical-private-synchronous:brightness \
        -h "int:value:$percent" "BRIGHTNESS ${percent}%"
fi
