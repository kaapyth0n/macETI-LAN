#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
swift build -c release -Xswiftc -gnone -Xswiftc -file-prefix-map -Xswiftc "$project_dir=."
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$project_dir/dist/macETI-LAN.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/MacETILAN" "$app_dir/Contents/MacOS/macETI-LAN"
cp "$binary_dir/maceti" "$app_dir/Contents/MacOS/maceti"
cp -R "$binary_dir/macETI-LAN_MacETICore.bundle" "$app_dir/Contents/Resources/"
bash scripts/build-icon.sh "$app_dir/Contents/Resources/AppIcon.icns"
# Remove local debug paths/symbols from the distributable executables.
strip -S "$app_dir/Contents/MacOS/macETI-LAN" "$app_dir/Contents/MacOS/maceti"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>macETI-LAN</string>
<key>CFBundleIdentifier</key><string>xyz.macetilan.desktop</string>
<key>CFBundleName</key><string>macETI-LAN</string>
<key>CFBundleDisplayName</key><string>macETI-LAN</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleShortVersionString</key><string>0.6.1</string>
<key>CFBundleVersion</key><string>8</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir/Contents/MacOS/maceti"
codesign --force --sign - "$app_dir"
printf 'Built %s\n' "$app_dir"
