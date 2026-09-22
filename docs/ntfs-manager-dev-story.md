# macOS에서 NTFS를 자유롭게: ntfs-manager 개발기

Windows 세상에서 흔히 쓰이는 NTFS 포맷 외장 드라이브. macOS에 꽂으면 읽기는
되는데 쓰기가 안 된다. Paragon NTFS나 Tuxera NTFS 같은 유료 드라이버를 사거나,
커널 확장을 깔거나, 그냥 exFAT로 다시 포맷하거나 — 선택지는 있지만 마땅한
무료 GUI 유틸리티가 없었다. 그래서 직접 만들었다. Dock에 뜨는 SwiftUI 앱 +
CLI + launchd 권한 헬퍼까지, 이 글은 그 과정의 기록이다.

## 목표

- macOS(Apple Silicon)에서 NTFS 볼륨 **읽기/쓰기**
- Dock 형태의 GUI 앱 — 터미널 명령 없이 마운트/언마운트/제거/복구
- 무료, 오픈소스, 개인용
- kext 없이, Reduced Security 없이

## 첫 번째 갈림길: "macOS가 지원하는 방식"은 존재하는가

가장 먼저 확인한 것: macOS의 내장 NTFS 지원은 **읽기 전용**이다. fstab으로 켜는
비공식 쓰기 모드가 존재하지만 데이터 손상 이력이 있어 선택지가 아니다.
Paragon 같은 유료 제품들도 결국 서드파티 드라이버를 얹는 방식이라 "공식
지원"이란 건 세상에 없다.

그래도 Apple이 공식 제공하는 프레임워크가 하나 있긴 했다 — **FSKit**
(macOS 15.4+, 유저스페이스 파일시스템 프레임워크). 실제로 `xntfs`,
`ntfskit` 같은 오픈소스가 libntfs-3g를 FSKit에 매핑해 구현하고 있다.
문제는 entitlement: `com.apple.developer.fskit.fsmodule`은 **restricted**
권한이라 유료 Apple Developer 계정 + Apple의 개별 승인이 필요하다. 승인
없이는 로컬 실행조차 AMFI가 막는다. 무료 경로로는 불가능 — 탈락.

남은 선택지:

| 방식 | 커널 확장 | 보안 설정 변경 | 비용 | 비고 |
|---|---|---|---|---|
| macFUSE + ntfs-3g | 필요 | Reduced Security 필요 | 무료 | Apple Silicon에서 kext는 번거로움 |
| **FUSE-T + ntfs-3g** | 불필요 | 불필요 | 무료 | NFS v4 loopback 방식 |
| FSKit | 불필요 | 불필요 | 유료 계정 + 승인 | entitlement 제한 |

**FUSE-T**를 선택했다. 커널 확장 대신 로컬 NFS v4 서버를 띄우고 macOS 내장
NFS 클라이언트가 마운트하는 구조라 kextless로 동작한다. ntfs-3g가
`/dev/diskNsM`을 읽고 쓰는 파일시스템 로직을 담당하고, FUSE-T가 그걸 커널이
인식하는 마운트로 변환한다.

```text
┌──────────────┐   POSIX I/O   ┌──────────┐  블록 I/O  ┌─────────────┐
│ Finder / 앱  │ ────────────► │ ntfs-3g  │ ─────────► │ /dev/disk4s1 │
└──────────────┘               └────┬─────┘            └─────────────┘
        ▲                           │
        │      NFS v4 loopback      │ FUSE 프로토콜
        │   (macOS 내장 클라이언트)   │
        │                    ┌──────┴──────┐
        └────────────────────│   FUSE-T    │
                             │ (go-nfsv4)  │
                             └─────────────┘
```

마운트 결과는 `mount`에서 이렇게 보인다:

```text
localhost:/My Passport on /Volumes/My Passport (nfs)
```

## 선택한 기술들 — 각각 뭐고 왜 썼나

### ntfs-3g — NTFS 읽기/쓰기 엔진

Tuxera가 만든 오픈소스 NTFS 드라이버(GPL-2.0+/LGPL). 리눅스 배포판들이
수십 년간 써온 검증된 구현체로, MFT·저널($LogFile)·보안 디스크립터 같은
NTFS 내부 구조를 전부 이해한다. 우리 앱은 파일시스템 로직을 직접 구현하지
않고 ntfs-3g를 서브프로세스로 실행한다 — GPL 바이너리를 링크하지 않고
프로세스 경계로 분리해서 우리 코드는 MIT로 둘 수 있었다. 함께 오는
`ntfsfix`(dirty 플래그/저널 리셋)는 앱의 "복구" 버튼이 호출한다.

### FUSE-T — kext 없는 FUSE

FUSE는 커널 파일시스템 코드를 유저 프로세스로 옮기는 프레임워크인데,
고전적 구현인 macFUSE는 커널 확장이 필요하다 — Apple Silicon에서는
Reduced Security까지 내려야 해서 배제했다. FUSE-T는 커널 확장 대신
**로컬 NFS v4 서버**(go-nfsv4)를 띄우고 macOS 내장 NFS 클라이언트가
마운트하는 방식이다. 성능은 커널 FUSE보다 낮지만(NFS 왕복 오버헤드)
보안 설정을 건드리지 않아 개인용 유틸리티엔 합리적인 트레이드오프였다.
`FUSE_NFSSRV_PATH` 환경 변수로 유저스페이스 설치(`~/.fuse-t`)도 지원한다.

### Swift + SwiftUI + SwiftPM

앱/CLI 전부 Swift. UI는 Dock에 뜨는 WindowGroup 기반 SwiftUI로 최소한의
코드로 볼륨 목록·버튼·배너를 구성했다. Xcode가 없는 환경이라 IDE 프로젝트
대신 **SwiftPM**(`Package.swift`)으로 멀티 타겟을 구성했다 — 라이브러리
`NTFSKit`, 앱 `NTFSManager`, CLI `ntfs-cli`, 데몬 `ntfs-helper` 4개 타겟이
같은 소스 트리에서 빌드된다. `.app` 번들은 `bundle-app.sh`가 Info.plist,
아이콘, lproj, 헬퍼 바이너리를 수동으로 조립해 만든다.

### DiskArbitration — 디스크 이벤트 감지

macOS의 디스크 이벤트 프레임워크. `DASession`에 appeared/disappeared/
descriptionChanged 콜백을 등록하면 드라이브를 꽂거나 뽑을 때 앱이 즉시
알 수 있다 — 폴링 없이 목록이 자동 갱신된다. 실제 볼륨 정보는 콜백이
올 때 `diskutil list -plist` + `diskutil info -plist`를 파싱해 채운다.

### osascript — MVP 권한 상승

`do shell script ... with administrator privileges`는 macOS가 내장한
권한 상승 장치로, 실행할 때마다 관리자 승인 대화상자가 뜬다. 별도
인프라 없이 root 명령을 띄울 수 있어 MVP엔 충분했지만, 매번 프롬프트가
뜨는 게 불편해서 헬퍼 데몬으로 대체했다. 지금도 헬퍼 미설치 시 폴백으로
남아있다.

### launchd 데몬 + UNIX 도메인 소켓 — 권한 헬퍼

"관리자 승인 1회" 이후 프롬프트 없이 디스크 작업을 하려면 root 데몬이
필요하다. IPC로 XPC 대신 **UNIX 소켓**을 택한 이유: XPC/NSXPC는
Mach 서비스라 클라이언트가 제대로 서명된 .app이어야 자연스럽고,
CLI 바이너리가 같은 채널을 쓰기 어렵다. 소켓은 파일 권한
(root:admin 0660)만으로 접근 제어가 되고, `ntfs-cli`에서도 똑같이 쓸 수
있다. 보안은 소켓 권한 + 명령 화이트리스트 + 인자 정규식 검증의 3중으로.

### TCC / Full Disk Access — 보이지 않는 벽

macOS의 동의 프레임워크. root 권한과 완전히 별개로, 물리 디스크 raw
device나 `~/Documents` 같은 보호 경로 접근은 "책임 프로세스"의 TCC 권한을
요구한다. 이 프로젝트에서 가장 덜 문서화된 함정이었다 — root 셸이
`/dev/disk4s1`을 열지 못하고, `~/Documents`의 빌드 산출물을 읽지 못한다.
앱은 EPERM을 감지하면 설정 창으로 바로 안내한다.

### hdiutil — 물리 디스크 없는 테스트

실제 NTFS 드라이브가 없어도 `hdiutil create -layout GPTSPUD`로 GPT
디스크 이미지를 만들고 attach하면 `/dev/diskNsM` 블록 디바이스가 생긴다.
이미지 디바이스는 연 사용자 소유라 포맷도 가능하다 — 테스트 전체
라이프사이클(감지→마운트→쓰기→제거)을 물리 하드웨어 없이 검증했다.

### iconutil + CoreGraphics — 코드로 그리는 아이콘

디자인 툴 없이 `make-icon.swift`가 CoreGraphics로 HDD 플래터+액추에이터
암을 그려 PNG를 만들고, iconset→`iconutil`로 `AppIcon.icns`를 생성한다.
아이콘 수정이 코드 diff로 리뷰되는 게 장점.

## 두 번째 함정: macOS용 ntfs-3g는 Homebrew에 없다

`brew install ntfs-3g`는 실패한다 — homebrew-core의 ntfs-3g는
`depends_on :linux`다. macOS용은 FUSE-T 개발자의 포크
(`macos-fuse-t/ntfs-3g`)를 소스 빌드해야 한다. 그래서 repo 자체를 Homebrew
tap으로 만들고 커스텀 formula(`Formula/ntfs-3g-fuset.rb`)를 뒀다:

```bash
brew tap <user>/ntfs-manager && brew install ntfs-3g-fuset
```

여기서 만난 함정들:

- **FUSE-T 경로에 공백** — `/Library/Application Support/fuse-t`를
  configure에 넘기면 경로가 깨진다. 공백 없는 심볼릭 링크로 우회.
- **빠진 unversioned 심볼릭 링크** — `libfuse-t-1.2.7.dylib`만 있고
  `libfuse-t.dylib`이 없어 링크 실패. 수동 생성.
- **Homebrew 빌드 샌드박스** — `LDFLAGS`에 `-lfuse-t`를 전역으로 넣으면
  configure의 conftest 실행 파일이 샌드박스 안에서 `Trace/BPT trap`으로
  죽는다. LDFLAGS에서 빼고 빌드 단계에서만 링크하도록 분리했다.
- **HOME 스크럽** — brew 빌드는 `HOME`을 임시 디렉토리로 바꿔치기해서
  `~/.fuse-t`를 못 찾는다. `Etc.getpwuid`로 진짜 홈을 조회하게 했다.

## 보너스 발견: FUSE-T는 sudo 없이 설치된다

FUSE-T pkg는 원래 sudo로 `/Library`에 설치되는데, pkg 페이로드를 뜯어보니
`~/.fuse-t` 유저스페이스 경로를 지원한다. `install-deps.sh`는
`brew fetch --cask fuse-t`로 받은 pkg를 **풀기만 해서** 사용자 홈에 깐다.
NFS가 `localhost`를 쓰므로 `/etc/hosts` 건드릴 필요도 없다. 결과적으로
의존성 설치 전 과정이 비밀번호 없이 돌아간다.

## 탐지: GPT 디스크의 NTFS는 "Microsoft Basic Data"로 뜬다

처음엔 `diskutil list`의 `Content` 필드가 `Windows_NTFS`인 파티션만 찾았는데,
실제 GPT 디스크는 이렇게 나온다:

```text
Content:        Microsoft Basic Data
FilesystemType: ntfs
```

`Content`는 파티션 타입 GUID 라벨이고, 실제 파일시스템 판별은
`diskutil info -plist`의 `FilesystemType == "ntfs"`로 해야 한다.
Content는 "NTFS일 수 있는 후보" 필터로만 쓰고(`Windows_NTFS`,
`Microsoft Basic Data` 등), 최종 판정은 FilesystemType으로 바꿨다.

## 권한의 미로: root인데 왜 EPERM이 뜨는가

ntfs-3g가 외부 FUSE 라이브러리로 블록 디바이스를 마운트하려면 root가
필요하다(ntfs-3g 자체가 비특권 유저 + 블록 디바이스 조합을 거부한다).
그래서 처음엔 `osascript "do shell script ... with administrator privileges"`로
관리자 승인을 받아 실행했다.

그런데 실제 2TB WD My Passport에 대고 하니, **root인데도**
`/dev/disk4s1` open이 `Operation not permitted`로 실패했다. 원인은
macOS의 TCC — 물리 디스크의 raw device 접근은 root 권한과 별개로
**전체 디스크 접근 권한(Full Disk Access)**이 필요하다. 재미있는 점은
거부된 바이너리(`ntfs-3g`)가 시스템 설정의 FDA 목록에 자동 등록된다는 것.
토글만 켜면 된다. 앱에는 이 케이스를 감지해 안내하는 로직과 설정 창을 여는
버튼을 넣었다.

비슷한 함정이 하나 더 있었다. 헬퍼 설치 시 root 셸이 `~/Documents` 안의
빌드 산출물을 읽지 못했다 — Documents 폴더도 TCC 보호 대상이라 root여도
차단된다. 바이너리를 `/tmp`에 스테이징한 뒤 설치하게 해서 해결.

그리고 ntfs-3g가 내뱉은 다음 에러:

```text
The NTFS partition is in an unsafe state. Please resume and shutdown
Windows fully (no hibernation or fast restarting)...
```

Windows가 최대절전/빠른시작 상태로 종료했거나 안전 제거 없이 뽑힌 dirty
볼륨이라는 뜻이다. 마운트 옵션에 `recover`를 추가해 ntfs-3g가 저널 복구를
자동 시도하게 했고, 그래도 안 되면 앱의 "복구" 버튼(ntfsfix)이나 Windows
chkdsk로 안내한다.

## launchd 권한 헬퍼: 비밀번호 프롬프트와의 결별

osascript 방식은 마운트할 때마다 비밀번호/Touch ID를 묻는다. 한두 번이야
괜찮지만 자동 마운트를 하려면 매번 팝업이 뜨는 건 말이 안 된다. 그래서
`ntfs-helper`라는 launchd 데몬을 만들었다:

- `/Library/PrivilegedHelperTools/ntfs-manager-helper` + LaunchDaemons plist
- `/var/run/ntfs-manager-helper.sock` (root:admin, 0660) UNIX 소켓 서버
- **셸 명령을 받지 않는다.** `EXEC`/`SPAWN`/`MKDIR`/`RMDIR`/`CLEARLOG`
  같은 구조화된 op만 받고, 실행 바이너리는 화이트리스트(diskutil,
  ntfs-3g, ntfsfix, umount), 인자는 정규식으로 검증한다
  (`^/dev/disk\d+s\d+$`, `^/Volumes/...`). 소켓을 열어도 임의 명령 실행으로
  이어지지 않게 설계했다.

프로토콜은 필드 구분자 `\x1F`(US), 내부 구분자 `\x1E`(RS)를 쓰는 단순한
텍스트 라인이고, 응답은 `EXIT <code>\x1F<stdout>\x1F<stderr>`를 EOF까지
읽는다.

```text
클라이언트                          헬퍼(root)
   │  "SPAWN␟/opt/…/ntfs-3g␟/var/log/…␟env␟args"  │
   │ ───────────────────────────────────────────►│  검증 → Process.run
   │  "EXIT 0␟spawned pid 1234␟"                  │
   │ ◄───────────────────────────────────────────│
```

설치는 `--install` 자기설치 모드로 — 자기 자신을
`/Library/PrivilegedHelperTools`에 복사하고 plist를 쓰고
`launchctl bootstrap`까지 한다. 클라이언트는 설치 시점에만 osascript로
1회 승인을 받고, 이후 모든 작업은 소켓으로 간다. 헬퍼가 안 떠 있으면
`AutoRunner`가 자동으로 osascript 프롬프트로 폴백한다.

부수 효과: op를 직접 `Process` 인자로 넘기니까 볼륨명 공백 같은 셸
인용 문제가 원천적으로 사라졌다.

## 잡다하지만 진짜였던 버그들

**볼륨명 공백**. `My Passport`가 `-o volname=My Passport`로 만들어지면서
인자가 쪼개져 파싱 실패. 옵션 문자열 통째로 인용해서 해결. (이후 헬퍼 경로
도입으로 아예 셸을 거치지 않게 됐다.)

**pgrep 파싱**. 마운트 확인을 `pgrep -fl ntfs-3g` 출력을 공백 split해서
했더니 `/Volumes/My Passport`가 `/Volumes/My`로 잘렸다. 마운트 감지는
됐는데 상태 표시와 언마운트가 깨지는 반쪽 버그. 디바이스 경로 뒤부터
` -o` 앞까지를 통째로 취하게 고쳤다.

**eject의 정규식**. `"disk6s1".components(separatedBy: "s")`가 `"di"`를
반환해서 `/dev/di`를 eject하던 시절이 있었다. `s\d+$` 정규식으로 교체.

**디스크 이미지 eject**. `diskutil eject`는 물리 디스크엔 되는데
`hdiutil attach`된 이미지엔 "Could not find disk"가 난다.
`hdiutil detach` 폴백 추가.

**WD 인클로저의 유령 노드**. eject가 성공해도 `disk4` 노드가 사라지지
않는다 — 인클로저가 계속 자신을 열거하는 특성. 볼륨이 언마운트됐으면 이미
안전하니, 앱은 성공 시 "안전하게 제거됨 — 케이블을 뽑아도 됩니다" 메시지를
보여주게 했다.

**mkntfs와 파티션 디바이스**. 테스트용 NTFS 이미지를 만들 때 mkntfs가
파티션 디바이스에 직접 쓰면 `add_attr_sd failed: Invalid argument`로
죽는다. 파일에 mkntfs → `dd`로 파티션 디바이스에 복사 → 재attach로
우회했다. 참고로 `hdiutil attach`한 이미지의 `/dev/diskNsM`은 연 사용자
소유라 이 과정에 root가 필요 없다.

**창 크기 기억**. macOS가 이전 창 프레임을 복원해서 `defaultSize`가
무시됐다. 유틸리티 창이라 `.windowResizability(.contentSize)`로 콘텐츠
크기에 고정.

## 구조

```text
ntfs-manager/
├── Package.swift                    # defaultLocalization: ko
├── Sources/
│   ├── NTFSKit/                     # 코어 라이브러리 (앱·CLI 공용)
│   │   ├── Models.swift             # Volume, MountState, 에러 타입
│   │   ├── DiskMonitor.swift        # DiskArbitration 이벤트 + diskutil 스캔
│   │   ├── MountService.swift       # 마운트/언마운트/제거/복구 오케스트레이션
│   │   ├── PrivilegedRunner.swift   # PrivilegedOp, Helper/Auto/Osascript runner
│   │   ├── Diagnostics.swift        # 의존성 감지 + ntfs-3g 에러 분류
│   │   └── Process+Run.swift        # Process 래퍼
│   ├── NTFSManager/                 # SwiftUI 앱
│   ├── ntfs-cli/                    # CLI (같은 NTFSKit 사용)
│   └── ntfs-helper/                 # launchd root 데몬
├── Scripts/
│   ├── install-deps.sh              # FUSE-T 유저스페이스 + tap + formula 설치
│   ├── bundle-app.sh                # .app 패키징 (헬퍼·lproj·아이콘 포함)
│   └── make-icon.swift              # 코드로 그리는 앱 아이콘
├── Formula/ntfs-3g-fuset.rb         # ntfs-3g 소스 빌드 formula
└── Resources/                       # AppIcon.icns, en.lproj, ko.lproj
```

## 라이선스 설계

- 앱/라이브러리 코드: **MIT**
- ntfs-3g: GPL-2.0+ — **서브프로세스로 실행**하므로 앱이 GPL로 오염되지
  않는다. brew로 별도 설치되고 바이너리를 번들에 포함하지 않는 것도 그 일환.
- FUSE-T: 무료지만 클로즈드소스 — 사용자 환경에 별도 설치되는 런타임
  의존성. README에 명시했다.

배포 관점에서 무료 계정은 notarization이 안 되므로 서명되지 않은 .app은
Gatekeeper 경고가 뜬다. 소스 배포 + 로컬 빌드가 기본 경로다.

## 마치며

"NTFS를 macOS에서 쓰기 가능하게"는 표면적으로 간단한 요구지만, 실제로는
Homebrew 패키징, TCC 권한 모델, launchd 권한 상승, 디스크 아비트레이션,
파일시스템 dirty 상태 같은 macOS의 속살을 하나씩 만나게 되는 프로젝트였다.
특히 "root인데 EPERM"처럼 유닉스 상식으로는 이상해 보이는 현상들이 전부
TCC라는 현대 macOS 보안 레이어에서 오는 게 흥미로웠다.

실제 2TB 드라이브에서 감지 → R/W 마운트 → 쓰기 → 언마운트 → 제거까지
검증했고, 헬퍼 설치 후에는 비밀번호 입력 없이 동작한다.

- 코드: `github.com/<user>/ntfs-manager` (MIT)
- 백엔드: FUSE-T + ntfs-3g, 전부 유저스페이스 — kext도 Reduced Security도
  없다.
