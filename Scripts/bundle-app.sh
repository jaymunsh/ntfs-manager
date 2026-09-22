#!/bin/bash
# SwiftPM 빌드 결과물을 NTFSManager.app 번들로 패키징
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO_ROOT/build/NTFSManager.app"
BINARY=ntfs-manager
VERSION=0.1.0

cd "$REPO_ROOT"
swift build -c release --product "$BINARY"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/$BINARY" "$APP/Contents/MacOS/NTFSManager"
cp "$REPO_ROOT/Scripts/install-deps.sh" "$APP/Contents/Resources/" 2>/dev/null || true
[ -f "$REPO_ROOT/Resources/AppIcon.icns" ] && cp "$REPO_ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>NTFS Manager</string>
    <key>CFBundleDisplayName</key><string>NTFS Manager</string>
    <key>CFBundleIdentifier</key><string>local.ntfs-manager</string>
    <key>CFBundleExecutable</key><string>NTFSManager</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# 로컬 실행용 ad-hoc 서명 (Gatekeeper 경고 완화)
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "==> $APP 생성 완료"
echo "    실행: open '$APP'"
