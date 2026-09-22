#!/bin/bash
# ntfs-manager 의존성 설치: FUSE-T + ntfs-3g (fuse-t 빌드)
# fuse-t pkg 설치는 관리자 권한이 필요해 비밀번호를 물을 수 있습니다.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> 1/3  FUSE-T 설치"
if [ -d "/Library/Application Support/fuse-t" ] || [ -e /usr/local/lib/libfuse-t.dylib ]; then
    echo "    FUSE-T 이미 설치됨 — 건너뜀"
else
    brew install --cask fuse-t
fi

echo "==> 2/3  로컬 tap 연결 (repo → homebrew tap)"
TAPS="$(brew --repository)/Library/Taps"
mkdir -p "$TAPS/ntfs-manager"
ln -sfn "$REPO_ROOT" "$TAPS/ntfs-manager/homebrew-ntfs-manager"

echo "==> 3/3  ntfs-3g (FUSE-T 빌드) 설치"
if command -v ntfs-3g &>/dev/null; then
    echo "    ntfs-3g 이미 설치됨 — 건너뜀"
else
    brew install ntfs-manager/ntfs-manager/ntfs-3g-fuset
fi

echo "==> 완료"
command -v ntfs-3g && ntfs-3g --version 2>/dev/null | head -1 || true
