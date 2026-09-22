import Foundation
import SwiftUI
import NTFSKit
import UserNotifications

@MainActor
final class VolumeStore: ObservableObject {
    @Published var volumes: [Volume] = []
    @Published var deps = Diagnostics.DependencyStatus(fuseT: false, ntfs3g: nil, ntfsfix: nil)
    @Published var busyVolumeIDs: Set<String> = []
    @Published var lastError: String?
    @Published var lastInfo: String?
    @Published var helperInstalled = false
    /// ""=시스템 언어, "ko", "en" — 앱 내 언어 오버라이드
    @Published var appLanguage: String {
        didSet { UserDefaults.standard.set(appLanguage, forKey: "appLanguage") }
    }

    private let monitor = DiskMonitor()
    private let service = MountService()
    private var seenVolumeIDs: Set<String> = []
    private var autoMountAttempted: Set<String> = []

    private var autoMountEnabled: Bool {
        UserDefaults.standard.bool(forKey: "autoMountRW")
    }

    init() {
        appLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        monitor.onChange = { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        monitor.start()
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
        refresh()
    }

    func refresh() {
        deps = Diagnostics.check()
        helperInstalled = HelperRunner.ping()
        let prev = seenVolumeIDs
        volumes = monitor.scan()
        seenVolumeIDs = Set(volumes.map(\.id))
        // 자동 마운트: 새로 나타난 볼륨만, 1회 시도
        if autoMountEnabled {
            for v in volumes where !prev.contains(v.id) && !autoMountAttempted.contains(v.id) {
                switch v.mountState {
                case .unmounted, .nativeReadOnly:
                    autoMountAttempted.insert(v.id)
                    mountRW(v)
                default: break
                }
            }
        }
    }

    func run(_ id: String, _ label: String, info: String? = nil,
             _ action: @escaping @Sendable () throws -> Void) {
        busyVolumeIDs.insert(id)
        lastError = nil
        lastInfo = nil
        Task.detached { [weak self] in
            var errorText: String?
            do { try action() } catch {
                errorText = fmt("%@ 실패: %@", label, Self.describe(error))
            }
            await MainActor.run {
                self?.busyVolumeIDs.remove(id)
                self?.lastError = errorText
                if errorText == nil { self?.lastInfo = info }
                self?.notify(title: label, body: errorText ?? info)
                self?.refresh()
            }
        }
    }

    func mountRW(_ v: Volume)   { let s = service; run(v.id, L("읽기/쓰기 마운트"), info: fmt("%@ 읽기/쓰기로 마운트됨", v.displayName)) { try s.mountReadWrite(v) } }
    func mountRO(_ v: Volume)   { let s = service; run(v.id, L("읽기 전용 마운트"), info: fmt("%@ 읽기 전용으로 마운트됨", v.displayName)) { try s.mountReadOnly(v) } }
    func unmount(_ v: Volume)   { let s = service; run(v.id, L("언마운트"), info: fmt("%@ 언마운트됨", v.displayName)) { try s.unmount(v) } }
    func eject(_ v: Volume)     { let s = service; run(v.id, L("제거"), info: fmt("%@ 안전하게 제거됨 — 이제 케이블을 뽑아도 됩니다", v.displayName)) { try s.eject(v) } }
    func repair(_ v: Volume)    { let s = service; run(v.id, L("복구"), info: fmt("%@ 복구 완료", v.displayName)) { try s.repair(v) } }

    func installHelper() {
        run("helper", L("권한 헬퍼 설치"), info: L("권한 헬퍼가 설치됐습니다 — 이후 작업은 관리자 승인 없이 실행됩니다")) {
            try HelperInstaller.install()
        }
    }

    private func notify(title: String, body: String?) {
        guard let body, !body.isEmpty else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    nonisolated static func describe(_ e: Error) -> String {
        guard let err = e as? NTFSManagerError else { return e.localizedDescription }
        switch err {
        case .dependencyMissing(let d): return fmt("%@이(가) 설치되어 있지 않습니다", d)
        case .unmountFailed(let m): return fmt("언마운트 실패 — %@", L(m))
        case .mountFailed(let m): return fmt("마운트 실패 — %@", L(m))
        case .hibernated: return L("Windows가 최대절전/빠른시작 상태로 종료된 볼륨입니다. Windows에서 완전히 종료 후 다시 연결하세요.")
        case .needsRepair: return L("볼륨이 dirty 상태입니다. 복구(ntfsfix)를 실행하거나 Windows에서 chkdsk를 실행하세요.")
        case .permissionDenied: return L("디스크 접근이 거부됐습니다. 시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한에서 ntfs-3g와 이 앱을 허용하세요.")
        case .cancelled: return L("사용자가 취소했습니다")
        }
    }
}

/// 앱 번들 로컬라이즈 — 키는 한국어 원문.
/// appLanguage 오버라이드가 있으면 해당 lproj 번들을 직접 조회한다 (즉시 전환, 재시작 불필요).
func L(_ key: String) -> String {
    let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
    guard !lang.isEmpty else { return NSLocalizedString(key, comment: "") }
    if let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
       let b = Bundle(path: path) {
        return b.localizedString(forKey: key, value: nil, table: nil)
    }
    return key
}
func fmt(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}
