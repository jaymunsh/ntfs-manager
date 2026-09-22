#!/bin/bash
# ntfs-manager 의존성 설치 — 전 과정 sudo 불필요.
#   1) FUSE-T: pkg 페이로드를 ~/Library/Application Support/fuse-t + ~/.fuse-t 에 유저스페이스 설치
#      (brew cask의 sudo pkg 설치 대신 수동 추출 — postinstall의 non-root 분기와 동일한 결과)
#   2) ntfs-3g: macos-fuse-t 포크를 소스 빌드해 /opt/homebrew 에 설치 (brew tap 경유)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FUSET_HOME="$HOME/Library/Application Support/fuse-t"
FUSE_USER_PREFIX="$HOME/.fuse-t"

echo "==> 1/3  FUSE-T 유저스페이스 설치"
if [ -d "$FUSET_HOME/lib" ]; then
    echo "    FUSE-T 이미 설치됨 — 건너뜀"
else
    PKG="$(brew fetch --cask fuse-t 2>&1 | grep -oE '/[^ ]+\.pkg' | head -1 || true)"
    if [ -z "$PKG" ] || [ ! -f "$PKG" ]; then
        PKG="$(find "$HOME/Library/Caches/Homebrew/Cask" -name 'fuse-t--*.pkg' | head -1)"
    fi
    [ -n "$PKG" ] || { echo "FUSE-T pkg 다운로드 실패"; exit 1; }

    TMP="$(mktemp -d)"
    pkgutil --expand-full "$PKG" "$TMP/x"
    mkdir -p "$FUSET_HOME"
    cp -R "$TMP/x/fuse-t-core.pkg/Payload/Library/Application Support/fuse-t/" "$FUSET_HOME"

    # postinstall의 non-root 분기 재현
    mkdir -p "$FUSE_USER_PREFIX/usr/local/bin" "$FUSE_USER_PREFIX/usr/local/include" "$FUSE_USER_PREFIX/usr/local/lib/pkgconfig"
    ln -sf "$FUSET_HOME/include/fuse"  "$FUSE_USER_PREFIX/usr/local/include/fuse"
    ln -sf "$FUSET_HOME/include/fuse3" "$FUSE_USER_PREFIX/usr/local/include/fuse3"
    ln -sf "$FUSET_HOME/bin/go-nfsv4-"* "$FUSE_USER_PREFIX/usr/local/bin/go-nfsv4"
    cp "$FUSET_HOME/lib/"libfuse-t-*.dylib "$FUSET_HOME/lib/"libfuse-t-*.a \
       "$FUSET_HOME/lib/"libfuse3.*.dylib "$FUSET_HOME/lib/"libfuse3.a \
       "$FUSE_USER_PREFIX/usr/local/lib/"
    cd "$FUSE_USER_PREFIX/usr/local/lib"
    ln -sf libfuse-t-*.dylib libfuse-t.dylib
    ln -sf libfuse-t-*.a libfuse-t.a
    ln -sf libfuse3.*.dylib libfuse3.dylib
    cp "$FUSET_HOME/pkgconfig/"*.pc "$FUSE_USER_PREFIX/usr/local/lib/pkgconfig/"
    rm -rf "$TMP"
    echo "    FUSE-T 설치 완료 → $FUSET_HOME"
fi

echo "==> 2/3  로컬 tap 연결 (repo → homebrew tap)"
if ! brew tap | grep -qx "ntfs-manager/ntfs-manager"; then
    brew tap ntfs-manager/ntfs-manager "$REPO_ROOT"
fi

echo "==> 3/3  ntfs-3g (FUSE-T 빌드) 설치"
if command -v ntfs-3g &>/dev/null; then
    echo "    ntfs-3g 이미 설치됨 — 건너뜀"
else
    brew install ntfs-manager/ntfs-manager/ntfs-3g-fuset
fi

echo "==> 완료"
command -v ntfs-3g && ntfs-3g --version 2>/dev/null | head -1 || true
