import Foundation

// ntfs-helper — launchd로 실행되는 root 데몬.
// 클라이언트(앱/CLI)가 UNIX 소켓으로 요청하면, 화이트리스트에 검증된
// 디스크 작업만 수행한다. 셸을 거치지 않고 Process로 직접 실행해 인젝션을 막는다.
//
// 프로토콜 (1 요청 = 1 연결):
//   요청:  OP <US> field <US> field ...   (US = 0x1F, env/args 내부는 RS = 0x1E)
//   응답:  "EXIT" SP <code> <US> <stdout> <US> <stderr>   — EOF까지 읽기

let socketPath = "/var/run/ntfs-manager-helper.sock"
let helperLabel = "com.leneu.ntfs-manager.helper"
let installedPath = "/Library/PrivilegedHelperTools/ntfs-manager-helper"
let plistPath = "/Library/LaunchDaemons/\(helperLabel).plist"
let US: UInt8 = 0x1F, RS: UInt8 = 0x1E

// MARK: - --install (root로 실행돼 자기 자신을 데몬으로 설치)

func selfInstall() -> Int32 {
    guard geteuid() == 0 else {
        FileHandle.standardError.write("helper install은 root 권한이 필요합니다\n".data(using: .utf8)!)
        return 1
    }
    let fm = FileManager.default
    let src = CommandLine.arguments[0]
    do {
        try fm.createDirectory(atPath: "/Library/PrivilegedHelperTools", withIntermediateDirectories: true)
        if fm.fileExists(atPath: installedPath) { try fm.removeItem(atPath: installedPath) }
        try fm.copyItem(atPath: src, toPath: installedPath)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedPath)
    } catch {
        FileHandle.standardError.write("헬퍼 복사 실패: \(error.localizedDescription)\n".data(using: .utf8)!)
        return 1
    }

    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key><string>\(helperLabel)</string>
        <key>ProgramArguments</key><array><string>\(installedPath)</string></array>
        <key>RunAtLoad</key><true/>
        <key>KeepAlive</key><true/>
        <key>StandardErrorPath</key><string>/var/log/ntfs-manager-helper.log</string>
    </dict>
    </plist>
    """
    do {
        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o644, .ownerAccountID: 0], ofItemAtPath: plistPath)
    } catch {
        FileHandle.standardError.write("plist 작성 실패: \(error.localizedDescription)\n".data(using: .utf8)!)
        return 1
    }

    // 재설치 대비 기존 데몬 제거 후 부트스트랩
    _ = try? Process.run(URL(fileURLWithPath: "/bin/launchctl"),
                         arguments: ["bootout", "system/\(helperLabel)"])
    let boot = Process()
    boot.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    boot.arguments = ["bootstrap", "system", plistPath]
    do {
        try boot.run(); boot.waitUntilExit()
        if boot.terminationStatus != 0 {
            FileHandle.standardError.write("launchctl bootstrap 실패 (\(boot.terminationStatus))\n".data(using: .utf8)!)
            return boot.terminationStatus
        }
    } catch {
        FileHandle.standardError.write("launchctl 실패: \(error.localizedDescription)\n".data(using: .utf8)!)
        return 1
    }
    print("helper installed and running")
    return 0
}

// MARK: - 명령 검증

let allowedExecPaths: Set<String> = [
    "/usr/sbin/diskutil", "/sbin/umount",
    "/opt/homebrew/bin/ntfs-3g", "/usr/local/bin/ntfs-3g",
    "/opt/homebrew/bin/ntfsfix", "/usr/local/bin/ntfsfix",
]

func validDevice(_ s: String) -> Bool {
    s.range(of: #"^/dev/disk\d+s\d+$"#, options: .regularExpression) != nil
}
func validWholeDisk(_ s: String) -> Bool {
    s.range(of: #"^/dev/disk\d+$"#, options: .regularExpression) != nil
}
func validMountPoint(_ s: String) -> Bool {
    s.hasPrefix("/Volumes/") && !s.contains("..") && !s.contains("\n")
        && s.range(of: #"^/Volumes/[^\x00-\x1F]+$"#, options: .regularExpression) != nil
}
func validArg(_ s: String) -> Bool {
    !s.isEmpty && s.range(of: #"[\x00-\x1F]"#, options: .regularExpression) == nil
}

/// EXEC 허용 여부 — 바이너리 화이트리스트 + 명령별 인자 검증
func execAllowed(path: String, args: [String]) -> Bool {
    guard allowedExecPaths.contains(path), let cmd = args.first else { return false }
    switch (path as NSString).lastPathComponent {
    case "diskutil":
        let sub = ["unmount", "unmountDisk", "eject", "mount"]
        guard sub.contains(cmd) else { return false }
        return args.dropFirst().allSatisfy {
            validDevice($0) || validWholeDisk($0) || validMountPoint($0) || $0 == "-readOnly"
        }
    case "umount":
        return args.count == 1 && validMountPoint(args[0])
    case "ntfsfix":
        return args.count == 1 && validDevice(args[0])
    default:
        return false
    }
}

/// SPAWN(ntfs-3g) 허용 여부: device mountpoint -o opts
func spawnAllowed(path: String, args: [String]) -> Bool {
    guard (path as NSString).lastPathComponent == "ntfs-3g",
          allowedExecPaths.contains(path),
          args.count == 4, args[2] == "-o" else { return false }
    return validDevice(args[0]) && validMountPoint(args[1]) && validArg(args[3])
}

// MARK: - 실행

nonisolated(unsafe) var children: [pid_t: Process] = [:]
nonisolated(unsafe) let childrenLock = NSLock()

func runSync(path: String, args: [String]) -> (Int32, String, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe(), err = Pipe()
    p.standardOutput = out; p.standardError = err
    do {
        try p.run()
    } catch {
        return (127, "", error.localizedDescription)
    }
    let o = out.fileHandleForReading.readDataToEndOfFile()
    let e = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
}

func spawn(path: String, args: [String], env: [String: String], log: String) -> (Int32, String, String) {
    FileManager.default.createFile(atPath: log, contents: nil)
    guard let fh = FileHandle(forWritingAtPath: log) else {
        return (1, "", "cannot open log \(log)")
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
    } catch {
        return (127, "", error.localizedDescription)
    }
    childrenLock.lock()
    children[p.processIdentifier] = p
    childrenLock.unlock()
    let pid = p.processIdentifier
    Thread.detachNewThread {
        p.waitUntilExit()
        childrenLock.lock(); children.removeValue(forKey: pid); childrenLock.unlock()
    }
    return (0, "spawned pid \(pid)", "")
}

// MARK: - 디스패치

func respond(code: Int32, _ out: String, _ err: String) -> Data {
    var d = Data("EXIT \(code)".utf8)
    d.append(US); d.append(out.data(using: .utf8)!)
    d.append(US); d.append(err.data(using: .utf8)!)
    return d
}

func dispatch(_ fields: [String]) -> Data {
    guard let op = fields.first else { return respond(code: 2, "", "empty request") }
    switch op {
    case "PING":
        return respond(code: 0, "PONG", "")

    case "EXEC":   // EXEC <US> path <US> args(RS-joined)
        guard fields.count >= 2 else { return respond(code: 2, "", "bad EXEC") }
        let path = fields[1]
        let args = fields.count > 2 ? fields[2].components(separatedBy: "\u{1E}") : []
        guard execAllowed(path: path, args: args) else {
            return respond(code: 2, "", "not allowed: \(path)")
        }
        let (c, o, e) = runSync(path: path, args: args)
        return respond(code: c, o, e)

    case "SPAWN":  // SPAWN <US> path <US> log <US> env(RS k=v) <US> args(RS)
        guard fields.count >= 5 else { return respond(code: 2, "", "bad SPAWN") }
        let (path, log) = (fields[1], fields[2])
        var env: [String: String] = [:]
        for kv in fields[3].components(separatedBy: "\u{1E}") where !kv.isEmpty {
            if let i = kv.firstIndex(of: "=") { env[String(kv[..<i])] = String(kv[kv.index(after: i)...]) }
        }
        let args = fields[4].components(separatedBy: "\u{1E}")
        guard log.hasPrefix("/var/log/") || log.hasPrefix("/tmp/") || log.contains("/Library/Logs/"),
              spawnAllowed(path: path, args: args) else {
            return respond(code: 2, "", "not allowed")
        }
        let (c, o, e) = spawn(path: path, args: args, env: env, log: log)
        return respond(code: c, o, e)

    case "MKDIR":  // MKDIR <US> path
        guard fields.count == 2, validMountPoint(fields[1])
                || fields[1].contains("/Library/ntfs-manager/") else {
            return respond(code: 2, "", "bad MKDIR")
        }
        do {
            try FileManager.default.createDirectory(atPath: fields[1], withIntermediateDirectories: true)
            return respond(code: 0, "", "")
        } catch { return respond(code: 1, "", error.localizedDescription) }

    case "RMDIR":
        guard fields.count == 2, validMountPoint(fields[1]) else {
            return respond(code: 2, "", "bad RMDIR")
        }
        do {
            try FileManager.default.removeItem(atPath: fields[1])
            return respond(code: 0, "", "")
        } catch { return respond(code: 1, "", error.localizedDescription) }

    case "CLEARLOG":
        guard fields.count == 2,
              fields[1] == "/var/log/ntfs-manager.log"
                || fields[1].contains("/Library/Logs/ntfs-manager.log") else {
            return respond(code: 2, "", "bad CLEARLOG")
        }
        FileManager.default.createFile(atPath: fields[1], contents: nil)
        return respond(code: 0, "", "")

    default:
        return respond(code: 2, "", "unknown op")
    }
}

// MARK: - 소켓 서버

func makeAddr() -> (sockaddr_un, socklen_t) {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        socketPath.withCString { cstr in
            strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cstr, 104)
        }
    }
    return (addr, socklen_t(MemoryLayout<sockaddr_un>.size))
}

func runServer() -> Never {
    unlink(socketPath)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { fatalError("socket() 실패") }
    var (addr, len) = makeAddr()
    let bound = withUnsafePointer(to: &addr) { p in
        p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
    }
    guard bound == 0 else { fatalError("bind 실패: \(errno)") }
    chmod(socketPath, 0o660)
    if let g = getgrnam("admin") { chown(socketPath, 0, g.pointee.gr_gid) }
    guard listen(fd, 8) == 0 else { fatalError("listen 실패") }

    while true {
        let c = accept(fd, nil, nil)
        if c < 0 { continue }
        var req = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(c, &buf, buf.count)
            if n <= 0 { break }
            req.append(buf, count: n)
            if req.count > 1 << 20 { break }
        }
        let fields = String(decoding: req, as: UTF8.self)
            .components(separatedBy: "\u{1F}")
        let res = dispatch(fields)
        _ = res.withUnsafeBytes { write(c, $0.baseAddress, res.count) }
        close(c)
    }
}

if CommandLine.arguments.contains("--install") {
    exit(selfInstall())
}
guard geteuid() == 0 else {
    FileHandle.standardError.write("ntfs-helper는 launchd(system 도메인)로 실행되어야 합니다\n".data(using: .utf8)!)
    exit(1)
}
runServer()
