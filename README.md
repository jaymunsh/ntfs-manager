# ntfs-manager

macOS(Apple Silicon)에서 NTFS 볼륨을 **읽기/쓰기**로 관리하는 유틸리티.
백엔드: [FUSE-T](https://www.fuse-t.org/) (kextless FUSE) + [ntfs-3g](https://github.com/macos-fuse-t/ntfs-3g).

- 커널 확장(kext) 없음 → Reduced Security 불필요
- Dock 앱(SwiftUI) + CLI(`ntfs-cli`) 제공
- 무료 — Apple Developer 계정 불필요

## 요구사항

- macOS 14+ (개발/테스트: macOS 26, M1 Max)
- Homebrew
- Xcode CLT (`xcode-select --install`) — 빌드용

## 설치

```bash
git clone <this-repo> && cd ntfs-manager
./Scripts/install-deps.sh   # FUSE-T + ntfs-3g 설치 (관리자 비밀번호 필요)
./Scripts/bundle-app.sh     # build/NTFSManager.app 생성
open build/NTFSManager.app
```

수동 설치:

```bash
brew install --cask fuse-t
brew tap <github-user>/ntfs-manager   # repo가 tap 형식(Formula/ 포함)
brew install ntfs-3g-fuset
```

## 사용

### 앱

NTFS 드라이브를 연결하면 목록에 표시됩니다. macOS가 읽기전용으로 자동 마운트한
볼륨은 "읽기/쓰기로 마운트" 버튼으로 재마운트합니다.

### CLI

```bash
.build/release/ntfs-cli deps       # 의존성 상태
.build/release/ntfs-cli list       # NTFS 볼륨 목록
.build/release/ntfs-cli mount-rw disk4s2   # 읽기/쓰기 마운트
.build/release/ntfs-cli unmount disk4s2
.build/release/ntfs-cli eject disk4s2
.build/release/ntfs-cli repair disk4s2     # ntfsfix
```

마운트 시 관리자 권한 프롬프트가 뜹니다 (ntfs-3g가 raw device 쓰기 접근에 root 필요).

## 주의사항

- Windows가 **최대절전모드/빠른시작** 상태로 종료된 볼륨은 ntfs-3g가 쓰기 마운트를
  거부합니다. Windows에서 완전히 종료(Shift+종료) 후 연결하세요.
- dirty 볼륨은 "복구"(ntfsfix) 또는 Windows의 chkdsk가 필요할 수 있습니다.
- FUSE-T는 NFS loopback 방식이라 대용량 파일 성능이 네이티브보다 낮을 수 있습니다.

## 라이선스

- 이 프로젝트(앱/라이브러리 코드): MIT
- ntfs-3g: GPL-2.0+/LGPL-2.0+ (서브프로세스로 실행, 링크 없음)
