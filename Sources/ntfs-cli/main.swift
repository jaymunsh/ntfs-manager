import Foundation
import NTFSKit

// ntfs-cli: 헤드리스 검증/CLI 인터페이스
//   ntfs-cli deps               의존성 상태 출력
//   ntfs-cli list               NTFS 볼륨 목록
//   ntfs-cli mount-rw <diskXsY> 읽기/쓰기 마운트
//   ntfs-cli mount-ro <diskXsY> 읽기전용 마운트
//   ntfs-cli unmount <diskXsY>  언마운트
//   ntfs-cli eject <diskXsY>    디스크 제거
//   ntfs-cli repair <diskXsY>   ntfsfix 복구
//   ntfs-cli install-helper     권한 헬퍼 설치(1회 관리자 승인)

func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

let args = Array(CommandLine.arguments.dropFirst())

func fail(_ e: Error) -> Never {
    let msg: String
    if let err = e as? NTFSManagerError {
        switch err {
        case .dependencyMissing(let d): msg = d + " " + L("미설치")
        case .unmountFailed(let m): msg = L("언마운트 실패: ") + m
        case .mountFailed(let m): msg = L("마운트 실패: ") + m
        case .hibernated: msg = L("Windows hibernation/fast-startup 상태 볼륨")
        case .needsRepair: msg = L("dirty 볼륨 — ntfsfix 또는 Windows chkdsk 필요")
        case .permissionDenied: msg = L("디스크 접근 거부 — 이 터미널/앱에 전체 디스크 접근 권한(Full Disk Access) 필요")
        case .cancelled: msg = L("취소됨")
        }
    } else { msg = e.localizedDescription }
    FileHandle.standardError.write("\(L("오류")): \(msg)\n".data(using: .utf8)!)
    exit(1)
}

func usage() -> Never {
    print("""
    \(L("사용법")): ntfs-cli <command> [diskXsY]
      deps | list | mount-rw | mount-ro | unmount | eject | repair | install-helper
    """)
    exit(0)
}

func find(_ id: String) throws -> Volume {
    guard let v = DiskMonitor().scan().first(where: { $0.id == id }) else {
        throw NTFSManagerError.mountFailed(L("볼륨을 찾을 수 없습니다") + " " + id)
    }
    return v
}

guard let cmd = args.first else { usage() }
let service = MountService()

do {
    switch cmd {
    case "deps":
        let d = Diagnostics.check()
        print("fuse-t:  \(d.fuseT ? L("설치됨") : L("미설치"))")
        print("ntfs-3g: \(d.ntfs3g ?? L("미설치"))")
        print("ntfsfix: \(d.ntfsfix ?? L("미설치"))")
        print("helper:  \(HelperRunner.ping() ? L("설치됨") : L("미설치"))")
    case "list":
        for v in DiskMonitor().scan() {
            let state: String = switch v.mountState {
            case .nativeReadOnly(let mp): "\(L("읽기전용"))(\(mp))"
            case .fuseTReadWrite(let mp): "\(L("읽기쓰기"))(\(mp))"
            case .unmounted: L("언마운트")
            case .busy: L("작업중")
            }
            print("\(v.id)\t\(v.displayName)\t\(ByteCountFormatter.string(fromByteCount: v.size, countStyle: .file))\t\(state)")
        }
    case "mount-rw": try service.mountReadWrite(try find(args.dropFirst().first ?? ""))
    case "mount-ro": try service.mountReadOnly(try find(args.dropFirst().first ?? ""))
    case "unmount":  try service.unmount(try find(args.dropFirst().first ?? ""))
    case "eject":    try service.eject(try find(args.dropFirst().first ?? ""))
    case "repair":   try service.repair(try find(args.dropFirst().first ?? ""))
    case "install-helper": try HelperInstaller.install()
    default: usage()
    }
} catch { fail(error) }
