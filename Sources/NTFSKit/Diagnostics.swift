import Foundation

/// 외부 의존성(fuse-t, ntfs-3g) 설치 상태와 볼륨 건강 상태를 진단한다.
public enum Diagnostics {

    public static let ntfs3gCandidates = [
        "/opt/homebrew/bin/ntfs-3g",
        "/usr/local/bin/ntfs-3g",
        "/opt/homebrew/sbin/ntfs-3g",
        "/usr/local/sbin/ntfs-3g",
    ]

    public static var ntfs3gPath: String? {
        ntfs3gCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// FUSE-T 설치 경로 (시스템 또는 유저스페이스)
    public static var fuseTPrefix: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for p in ["/usr/local", "\(home)/.fuse-t/usr/local"] {
            let libs = (try? FileManager.default.contentsOfDirectory(atPath: "\(p)/lib")) ?? []
            if libs.contains(where: { $0.hasPrefix("libfuse-t") && $0.hasSuffix(".dylib") }) {
                return p
            }
        }
        return nil
    }

    public static var fuseTInstalled: Bool {
        fuseTPrefix != nil
            || FileManager.default.fileExists(
                atPath: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/fuse-t").path)
    }

    public static var ntfsfixPath: String? {
        ["/opt/homebrew/bin/ntfsfix", "/usr/local/bin/ntfsfix"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public struct DependencyStatus {
        public var fuseT: Bool
        public var ntfs3g: String?
        public var ntfsfix: String?
        public var ready: Bool { fuseT && ntfs3g != nil }

        public init(fuseT: Bool, ntfs3g: String? = nil, ntfsfix: String? = nil) {
            self.fuseT = fuseT
            self.ntfs3g = ntfs3g
            self.ntfsfix = ntfsfix
        }
    }

    public static func check() -> DependencyStatus {
        DependencyStatus(fuseT: fuseTInstalled, ntfs3g: ntfs3gPath, ntfsfix: ntfsfixPath)
    }

    /// ntfs-3g stderr에서 거부 사유를 분류한다.
    public static func classify(ntfs3gStderr: String) -> NTFSManagerError? {
        let s = ntfs3gStderr.lowercased()
        if s.contains("hibernated") || s.contains("fast startup") || s.contains("windows is hibernated") {
            return .hibernated
        }
        if s.contains("unclean shutdown") || s.contains("run chkdsk") || s.contains("volume is dirty")
            || s.contains("mark for chkdsk") || s.contains("corrupt") {
            return .needsRepair
        }
        return nil
    }
}
