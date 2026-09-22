#!/bin/bash
# SwiftPM 빌드 결과물을 NTFSManager.app 번들로 패키징
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO_ROOT/build/NTFSManager.app"
BINARY=ntfs-manager
VERSION=0.1.0

cd "$REPO_ROOT"
swift build -c release --product "$BINARY" --product ntfs-helper

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/$BINARY" "$APP/Contents/MacOS/NTFSManager"
# 권한 헬퍼 — 사용자가 앱에서 1회 관리자 승인으로 설치할 수 있도록 동봉
cp ".build/release/ntfs-helper" "$APP/Contents/MacOS/ntfs-helper" 2>/dev/null || true
cp "$REPO_ROOT/Scripts/install-deps.sh" "$APP/Contents/Resources/" 2>/dev/null || true
[ -f "$REPO_ROOT/Resources/AppIcon.icns" ] && cp "$REPO_ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
# 로컬라이제이션 (ko는 리터럴 키 자체가 한국어 — en.lproj만 배포)
for lproj in "$REPO_ROOT"/Resources/*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done

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
    <key>CFBundleDevelopmentRegion</key><string>ko</string>
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
