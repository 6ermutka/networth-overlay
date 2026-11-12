#!/bin/zsh
# Собирает «Networth Overlay.app» в папку build (нужны Xcode Command Line Tools).
# Версия берётся из файла VERSION, адрес репозитория для проверки обновлений — из файла REPO (owner/name).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
REPO="$(tr -d '[:space:]' < REPO 2>/dev/null || true)"
APP="build/Networth Overlay.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Универсальный бинарник: Apple Silicon и Intel.
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" Sources/*.swift -o "build/NetworthOverlay-$arch"
done
lipo -create build/NetworthOverlay-arm64 build/NetworthOverlay-x86_64 -output "$APP/Contents/MacOS/NetworthOverlay"
rm build/NetworthOverlay-arm64 build/NetworthOverlay-x86_64

# Иконка: из icon/AppIcon.png (перерисовать — swift icon/make-icon.swift icon) делаем .icns всех размеров.
SET="build/AppIcon.iconset"
rm -rf "$SET"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s icon/AppIcon.png --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) icon/AppIcon.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$SET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>NetworthOverlay</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIdentifier</key><string>local.networth-overlay</string>
	<key>CFBundleName</key><string>Networth Overlay</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>NWORepository</key><string>$REPO</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Готово: $PWD/$APP (версия $VERSION)"
