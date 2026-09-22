import Foundation

/// NTFS 볼륨의 마운트/언마운트/제거를 오케스트레이션한다.
public final class MountService: Sendable {
    private let runner: PrivilegedRunner

    public init(runner: PrivilegedRunner = OsascriptRunner()) {
        self.runner = runner
    }

    /// 네이티브 RO 마운트를 내리고 ntfs-3g(FUSE-T)로 RW 마운트.
    public func mountReadWrite(_ v: Volume) throws {
        guard let ntfs3g = Diagnostics.ntfs3gPath else {
            throw NTFSManagerError.dependencyMissing("ntfs-3g")
        }
        guard Diagnostics.fuseTInstalled else {
            throw NTFSManagerError.dependencyMissing("FUSE-T")
        }

        // 1) 네이티브 마운트가 있으면 내린다
        if case .nativeReadOnly(let mp) = v.mountState {
            let r = try CommandRunner.run("/usr/sbin/diskutil", ["unmount", mp])
            guard r.exitCode == 0 else {
                throw NTFSManagerError.unmountFailed(r.stderr.isEmpty ? r.stdout : r.stderr)
            }
        }

        // 2) 마운트포인트 준비 (이름 충돌 시 suffix)
        let base = "/Volumes/\(v.displayName)"
        var mountPoint = base
        var n = 1
        while FileManager.default.fileExists(atPath: mountPoint), !Self.isEmptyDir(mountPoint) {
            n += 1
            mountPoint = "\(base) \(n)"
        }
        try FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

        // 3) ntfs-3g를 root로 백그라운드 실행
        //    유저스페이스 FUSE-T는 FUSE_NFSSRV_PATH로 go-nfsv4 위치를 넘긴다
        let uid = getuid(), gid = getgid()
        let opts = "local,allow_other,auto_xattr,auto_cache,noatime,windows_names,streams_interface=openxattr,inherit,uid=\(uid),gid=\(gid),volname=\(v.displayName)"
        var envPrefix = "HOME=\"\(NSHomeDirectory())\" "
        if let prefix = Diagnostics.fuseTPrefix {
            envPrefix += "FUSE_NFSSRV_PATH=\"\(prefix)/bin/go-nfsv4\" "
        }
        let cmd = "\(envPrefix)\"\(ntfs3g)\" \"\(v.devicePath)\" \"\(mountPoint)\" -o \(opts) </dev/null >/var/log/ntfs-manager.log 2>&1 &"
        let res = try runner.runAsRoot(cmd)
        guard res.exitCode == 0 else {
            throw NTFSManagerError.mountFailed(res.stderr.isEmpty ? res.stdout : res.stderr)
        }

        // 4) 마운트 완료 대기 + 에러 분류
        var mounted = false
        for _ in 0..<30 {
            Thread.sleep(forTimeInterval: 0.5)
            if DiskMonitor.fuseTMountPoint(for: v.id) != nil { mounted = true; break }
            if Self.mountLogContainsFailure() { break }
        }
        if !mounted {
            let log = Self.recentMountLog()
            if let err = Diagnostics.classify(ntfs3gStderr: log) { throw err }
            throw NTFSManagerError.mountFailed(log.isEmpty ? "ntfs-3g 마운트 실패" : log)
        }
    }

    /// macOS 네이티브 읽기전용으로 마운트
    public func mountReadOnly(_ v: Volume) throws {
        let r = try CommandRunner.run("/usr/sbin/diskutil", ["mount", "-readOnly", v.devicePath])
        guard r.exitCode == 0 else {
            throw NTFSManagerError.mountFailed(r.stderr.isEmpty ? r.stdout : r.stderr)
        }
    }

    public func unmount(_ v: Volume) throws {
        switch v.mountState {
        case .nativeReadOnly(let mp), .fuseTReadWrite(let mp):
            let r = try CommandRunner.run("/usr/sbin/diskutil", ["unmount", mp])
            if r.exitCode != 0 {
                // FUSE-T는 umount fallback
                let u = try CommandRunner.run("/sbin/umount", [mp])
                guard u.exitCode == 0 else {
                    throw NTFSManagerError.unmountFailed(r.stderr.isEmpty ? r.stdout : r.stderr)
                }
            }
        case .unmounted:
            return
        case .busy:
            throw NTFSManagerError.unmountFailed("볼륨이 사용 중입니다")
        }
    }

    /// 볼륨이 속한 전체 디스크를 제거(eject)한다.
    public func eject(_ v: Volume) throws {
        let disk = v.id.components(separatedBy: "s").first ?? v.id
        try unmount(v)
        let r = try CommandRunner.run("/usr/sbin/diskutil", ["eject", "/dev/\(disk)"])
        guard r.exitCode == 0 else {
            throw NTFSManagerError.unmountFailed(r.stderr.isEmpty ? r.stdout : r.stderr)
        }
    }

    /// ntfsfix로 간단 복구(dirty flag, journal 리셋)
    public func repair(_ v: Volume) throws {
        guard let ntfsfix = Diagnostics.ntfsfixPath else {
            throw NTFSManagerError.dependencyMissing("ntfsfix")
        }
        let res = try runner.runAsRoot("\"\(ntfsfix)\" \"\(v.devicePath)\"")
        guard res.exitCode == 0 else {
            throw NTFSManagerError.mountFailed(res.stderr.isEmpty ? res.stdout : res.stderr)
        }
    }

    // MARK: - helpers

    static func isEmptyDir(_ path: String) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: path).isEmpty) ?? false
    }

    static func recentMountLog() -> String {
        guard let s = try? String(contentsOfFile: "/var/log/ntfs-manager.log", encoding: .utf8) else { return "" }
        return String(s.split(separator: "\n").suffix(20).joined(separator: "\n"))
    }

    static func mountLogContainsFailure() -> Bool {
        let log = recentMountLog().lowercased()
        return log.contains("error") || log.contains("failed") || log.contains("hibernated")
            || log.contains("denied") || log.contains("cannot mount")
    }
}
