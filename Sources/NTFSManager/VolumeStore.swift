import Foundation
import SwiftUI
import NTFSKit

@MainActor
final class VolumeStore: ObservableObject {
    @Published var volumes: [Volume] = []
    @Published var deps = Diagnostics.DependencyStatus(fuseT: false, ntfs3g: nil, ntfsfix: nil)
    @Published var busyVolumeIDs: Set<String> = []
    @Published var lastError: String?

    private let monitor = DiskMonitor()
    private let service = MountService()

    init() {
        monitor.onChange = { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        monitor.start()
        refresh()
    }

    func refresh() {
        deps = Diagnostics.check()
        volumes = monitor.scan()
    }

    func run(_ id: String, _ label: String, _ action: @escaping @Sendable () throws -> Void) {
        busyVolumeIDs.insert(id)
        lastError = nil
        Task.detached { [weak self] in
            var errorText: String?
            do { try action() } catch {
                errorText = "\(label) 실패: \(Self.describe(error))"
            }
            await MainActor.run {
                self?.busyVolumeIDs.remove(id)
                self?.lastError = errorText
                self?.refresh()
            }
        }
    }

    func mountRW(_ v: Volume)   { let s = service; run(v.id, "쓰기 마운트") { try s.mountReadWrite(v) } }
    func mountRO(_ v: Volume)   { let s = service; run(v.id, "읽기 마운트") { try s.mountReadOnly(v) } }
    func unmount(_ v: Volume)   { let s = service; run(v.id, "언마운트") { try s.unmount(v) } }
    func eject(_ v: Volume)     { let s = service; run(v.id, "제거") { try s.eject(v) } }
    func repair(_ v: Volume)    { let s = service; run(v.id, "복구") { try s.repair(v) } }

    nonisolated static func describe(_ e: Error) -> String {
        guard let err = e as? NTFSManagerError else { return e.localizedDescription }
        switch err {
        case .dependencyMissing(let d): return "\(d)이(가) 설치되어 있지 않습니다"
        case .unmountFailed(let m): return "언마운트 실패 — \(m)"
        case .mountFailed(let m): return "마운트 실패 — \(m)"
        case .hibernated: return "Windows가 최대절전/빠른시작 상태로 종료된 볼륨입니다. Windows에서 완전히 종료 후 다시 연결하세요."
        case .needsRepair: return "볼륨이 dirty 상태입니다. 복구(ntfsfix)를 실행하거나 Windows에서 chkdsk를 실행하세요."
        case .permissionDenied: return "디스크 접근이 거부됐습니다. 시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한에서 ntfs-3g와 이 앱을 허용하세요."
        case .cancelled: return "사용자가 취소했습니다"
        }
    }
}
