# ntfs-manager

macOS(Apple Silicon)에서 NTFS 볼륨을 **읽기/쓰기**로 관리하는 유틸리티.
백엔드: [FUSE-T](https://www.fuse-t.org/) (kextless FUSE) + [ntfs-3g](https://github.com/macos-fuse-t/ntfs-3g).

- 커널 확장(kext) 없음 → Reduced Security 불필요
- Dock 앱(SwiftUI) + CLI(`ntfs-cli`) 제공
- **설치 과정 전체가 sudo 불필요** — FUSE-T는 유저스페이스(`~/.fuse-t`)에 설치
- 실제 디스크 RW 마운트 시에만 관리자 권한 프롬프트 1회 (raw device 접근)
- 물리 디스크 사용 시 **전체 디스크 접근 권한(Full Disk Access)** 필요 — 아래 참조

## 요구사항

- macOS 14+ (개발/테스트: macOS 26, M1 Max)
- Homebrew
- Xcode CLT (`xcode-select --install`) — 빌드용

## 설치

```bash
git clone <this-repo> && cd ntfs-manager
./Scripts/install-deps.sh   # FUSE-T(유저스페이스) + ntfs-3g — 비밀번호 없이 설치
./Scripts/bundle-app.sh     # build/NTFSManager.app 생성
open build/NTFSManager.app
```

내부 동작:
1. `brew fetch --cask fuse-t`로 pkg를 받아 페이로드를 `~/Library/Application Support/fuse-t`와
   `~/.fuse-t`에 풀어놓습니다 (brew의 sudo pkg 설치 대신 postinstall의 non-root 경로 재현)
2. 이 repo를 로컬 tap으로 등록하고 `ntfs-3g-fuset` formula를 빌드해 `/opt/homebrew`에 설치

GitHub에 올라간 후에는: `brew install --cask fuse-t` 또는 위 스크립트,
`brew tap <user>/ntfs-manager && brew install ntfs-3g-fuset`

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

실제 디스크 마운트 시 관리자 권한 프롬프트가 뜹니다
(ntfs-3g가 `/dev/diskXsY` 쓰기 접근에 root 필요 — 파일시스템 스택 자체는 유저스페이스).

### 전체 디스크 접근 권한 (필수)

macOS의 TCC 때문에 root 권한과 별개로, 물리 디스크의 raw device 접근에는
**전체 디스크 접근 권한(Full Disk Access)**이 필요합니다. 첫 마운트 시도에서
`Operation not permitted`가 뜨면:

1. 시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한
   (앱 하단 "디스크 권한 설정" 버튼으로 바로 열 수 있습니다)
2. 목록에 자동 추가된 **`ntfs-3g` 토글 ON** — 실제 디스크를 여는 바이너리
3. `+`로 **NTFSManager.app**도 추가 (앱 경로로 실행할 때 책임 프로세스)
   - CLI로 쓰는 경우 실행 중인 터미널 앱(Ghostty, Terminal 등)에도 부여
4. `ntfsfix`로 복구할 때도 같은 권한이 필요합니다 (첫 거부 시 목록에 자동 추가됨)

디스크 이미지 파일만 다루는 경우 이 권한은 필요 없습니다.

## 주의사항

- Windows가 **최대절전모드/빠른시작** 상태로 종료된 볼륨은 ntfs-3g가 쓰기 마운트를
  거부합니다. Windows에서 완전히 종료(Shift+종료) 후 연결하세요.
- dirty 볼륨은 마운트 시 ntfs-3g `recover`로 저널 복구를 자동 시도하고,
  그래도 거부되면 "복구"(ntfsfix) 또는 Windows의 chkdsk가 필요합니다.
- FUSE-T는 NFS loopback 방식이라 대용량 파일 성능이 네이티브보다 낮을 수 있습니다.
- 검증됨: NTFS 이미지 파일에서 마운트·읽기·쓰기·언마운트 라운드트립 동작 확인.

## 라이선스

- 이 프로젝트(앱/라이브러리 코드): MIT
- ntfs-3g: GPL-2.0+/LGPL-2.0+ (서브프로세스로 실행, 링크 없음)
- FUSE-T: fuse-t.org 배포 바이너리 (무료)
