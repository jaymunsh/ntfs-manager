import Foundation

/// NTFS 볼륨의 마운트/언마운트/제거를 오케스트레이션한다.
public final class MountService: Sendable {
    private let runner: PrivilegedRunner

    public init(runner: PrivilegedRunner = AutoRunner()) {
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
        //    /Volumes는 root 전용이므로, 유저 마운트(이미지 등)는 ~/Library/ntfs-manager/Volumes
        //    ntfs-3g는 블록 디바이스를 비특권 유저로 external FUSE 마운트하는 것을 거부 →
        //    일반 파일(디스크 이미지)만 유저 마운트, 블록 디바이스는 항상 root
        var st = stat()
        let needsRoot = !(stat(v.devicePath, &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG)
        let baseDir = needsRoot ? "/Volumes"
            : "\(NSHomeDirectory())/Library/ntfs-manager/Volumes"
        let base = "\(baseDir)/\(v.displayName)"
        var mountPoint = base
        var n = 1
        while FileManager.default.fileExists(atPath: mountPoint), !Self.isEmptyDir(mountPoint) {
            n += 1
            mountPoint = "\(base) \(n)"
        }
        if needsRoot {
            _ = try? runner.run(.mkdir(mountPoint))
        }
        try FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

        // 3) ntfs-3g 백그라운드 실행
        //    디바이스가 유저 쓰기 가능하면(disk image 등) root 불필요 — 직접 실행.
        //    실제 물리 디스크(/dev/disk* root:operator)만 관리자 권한 사용.
        let uid = getuid(), gid = getgid()
        let opts = "local,allow_other,auto_xattr,auto_cache,noatime,windows_names,streams_interface=openxattr,inherit,recover,uid=\(uid),gid=\(gid),volname=\(v.displayName)"
        var env: [String: String] = ["HOME": NSHomeDirectory()]
        if let prefix = Diagnostics.fuseTPrefix {
            env["FUSE_NFSSRV_PATH"] = "\(prefix)/bin/go-nfsv4"
        }
        let logPath = needsRoot ? "/var/log/ntfs-manager.log" : "\(NSHomeDirectory())/Library/Logs/ntfs-manager.log"
        try? FileManager.default.createDirectory(
            atPath: (logPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        // 이전 실패 로그가 판정을 오염시키지 않도록 둘 다 비운다
        let userLog = NSHomeDirectory() + "/Library/Logs/ntfs-manager.log"
        try? "".write(toFile: userLog, atomically: true, encoding: .utf8)
        if needsRoot {
            _ = try? runner.run(.clearLog("/var/log/ntfs-manager.log"))
        } else {
            try? "".write(toFile: "/var/log/ntfs-manager.log", atomically: true, encoding: .utf8)
        }

        let res: CommandResult
        if needsRoot {
            res = try runner.run(.spawn(path: ntfs3g,
                                        args: [v.devicePath, mountPoint, "-o", opts],
                                        env: env, log: logPath))
        } else {
            // 유저 마운트: 로컬에서 직접 백그라운드 실행
            res = Self.spawnLocal(path: ntfs3g,
                                  args: [v.devicePath, mountPoint, "-o", opts],
                                  env: env, log: logPath)
        }
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
            // 실패 시 만들어둔 빈 마운트포인트 디렉토리 정리
            if Self.isEmptyDir(mountPoint) {
                if needsRoot { _ = try? runner.run(.rmdir(mountPoint)) }
                try? FileManager.default.removeItem(atPath: mountPoint)
            }
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
                    let out = r.stderr.isEmpty ? r.stdout : r.stderr
                    if Self.isBusy(out) {
                        throw NTFSManagerError.unmountFailed(
                            "볼륨을 사용 중입니다. 열린 파일·Finder 창을 닫고 다시 시도하세요.")
                    }
                    throw NTFSManagerError.unmountFailed(out)
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
        let disk = v.id.replacingOccurrences(of: #"s\d+$"#, with: "",
                                             options: .regularExpression)
        try unmount(v)
        let r = try CommandRunner.run("/usr/sbin/diskutil", ["eject", "/dev/\(disk)"])
        if r.exitCode != 0 {
            // 디스크 이미지(hdiutil attach)는 diskutil eject가 안 먹힘 → detach fallback
            let d = try CommandRunner.run("/usr/bin/hdiutil", ["detach", "/dev/\(disk)"])
            guard d.exitCode == 0 else {
                throw NTFSManagerError.unmountFailed(r.stderr.isEmpty ? r.stdout : r.stderr)
            }
        }
    }

    /// ntfsfix로 간단 복구(dirty flag, journal 리셋)
    public func repair(_ v: Volume) throws {
        guard let ntfsfix = Diagnostics.ntfsfixPath else {
            throw NTFSManagerError.dependencyMissing("ntfsfix")
        }
        let res = try runner.run(.exec(path: ntfsfix, args: [v.devicePath]))
        guard res.exitCode == 0 else {
            let out = res.stderr.isEmpty ? res.stdout : res.stderr
            if let err = Diagnostics.classify(ntfs3gStderr: out) { throw err }
            throw NTFSManagerError.mountFailed(out)
        }
    }

    // MARK: - helpers

    /// 유저 권한으로 ntfs-3g 백그라운드 실행 (디스크 이미지 등 블록 디바이스가 아닌 경우)
    static func spawnLocal(path: String, args: [String], env: [String: String], log: String) -> CommandResult {
        FileManager.default.createFile(atPath: log, contents: nil)
        guard let fh = FileHandle(forWritingAtPath: log) else {
            return CommandResult(exitCode: 1, stdout: "", stderr: "cannot open log")
        }
        fh.seekToEndOfFile()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        var e = ProcessInfo.processInfo.environment
        for (k, v) in env { e[k] = v }
        p.environment = e
        p.standardOutput = fh; p.standardError = fh
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
            Thread.detachNewThread { p.waitUntilExit() }   // 좀비 방지
            return CommandResult(exitCode: 0, stdout: "spawned", stderr: "")
        } catch {
            return CommandResult(exitCode: 1, stdout: "", stderr: error.localizedDescription)
        }
    }

    static func isBusy(_ output: String) -> Bool {
        let s = output.lowercased()
        return s.contains("busy") || s.contains("in use") || s.contains("dissenter")
    }

    static func isEmptyDir(_ path: String) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: path).isEmpty) ?? false
    }

    static func recentMountLog() -> String {
        let paths = [
            NSHomeDirectory() + "/Library/Logs/ntfs-manager.log",
            "/var/log/ntfs-manager.log",
        ]
        var combined = ""
        for p in paths {
            if let s = try? String(contentsOfFile: p, encoding: .utf8) {
                combined += s + "\n"
            }
        }
        return String(combined.split(separator: "\n").suffix(20).joined(separator: "\n"))
    }

    static func mountLogContainsFailure() -> Bool {
        let log = recentMountLog().lowercased()
        return log.contains("error") || log.contains("failed") || log.contains("hibernated")
            || log.contains("denied") || log.contains("cannot mount")
    }
}
