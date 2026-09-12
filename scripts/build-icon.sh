#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
icon_output="${1:-$project_dir/dist/AppIcon.icns}"
icon_work="$(mktemp -d "${TMPDIR:-/tmp}/maceti-icon.XXXXXX")"
trap 'rm -rf "$icon_work"' EXIT
mkdir -p "$icon_work/AppIcon.iconset" "$(dirname "$icon_output")"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$project_dir/assets/AppIcon.png" \
        --out "$icon_work/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -z "$double_size" "$double_size" "$project_dir/assets/AppIcon.png" \
        --out "$icon_work/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_work/AppIcon.iconset" -o "$icon_output"
