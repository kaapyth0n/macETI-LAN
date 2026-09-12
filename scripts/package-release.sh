#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
bash scripts/build-app.sh
app_dir="$project_dir/dist/macETI-LAN.app"
app_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_dir/Contents/Info.plist")"
app_arch="$(lipo -archs "$app_dir/Contents/MacOS/macETI-LAN")"
if [[ "$app_arch" != "arm64" && "$app_arch" != "x86_64" ]]; then
    printf 'Unexpected build architecture: %s\n' "$app_arch" >&2
    exit 1
fi
release_name="macETI-LAN-v${app_version}-macos-${app_arch}"
release_work="$(mktemp -d "${TMPDIR:-/tmp}/maceti-release.XXXXXX")"
trap 'rm -rf "$release_work"' EXIT
release_folder="$release_work/$release_name"
mkdir -p "$release_folder/tools"
ditto --norsrc --noextattr "$app_dir" "$release_folder/macETI-LAN.app"
cp docs/INSTALL.md "$release_folder/README.md"
cp LICENSE THIRD_PARTY_NOTICES.md "$release_folder/"
cp scripts/bootstrap-catalog.py scripts/import-artwork.py "$release_folder/tools/"
codesign --verify --deep --strict "$release_folder/macETI-LAN.app"
ditto -c -k --norsrc --noextattr --keepParent "$release_folder" "$project_dir/dist/$release_name.zip"
(cd dist && shasum -a 256 "$release_name.zip" > "$release_name.zip.sha256")
printf 'Release: %s\n' "$project_dir/dist/$release_name.zip"
