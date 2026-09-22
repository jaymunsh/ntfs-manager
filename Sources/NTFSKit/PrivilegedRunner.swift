import Foundation

/// root 권한이 필요한 작업 단위. 셸 문자열이 아닌 구조화된 op로 전달해
/// 헬퍼 데몬(UNIX 소켓)과 osascript 양쪽에서 안전하게 실행할 수 있게 한다.
public enum PrivilegedOp: Sendable {
    /// 바이너리 직접 실행(동기). args는 프로세스 인자이며 셸 해석되지 않는다.
    case exec(path: String, args: [String])
    /// 백그라운드 실행 — stdout/stderr를 log에 append, 즉시 복귀.
    case spawn(path: String, args: [String], env: [String: String], log: String)
    case mkdir(String)
    case rmdir(String)
    case clearLog(String)
}

public protocol PrivilegedRunner: Sendable {
    func run(_ op: PrivilegedOp) throws -> CommandResult
    /// true면 비밀번호 프롬프트 없이 실행 가능(설치된 헬퍼 사용 중)
    var isHelper: Bool { get }
}

// MARK: - 헬퍼 데몬 클라이언트

public enum HelperError: Error, Sendable { case unavailable }

public final class HelperRunner: PrivilegedRunner {
    public static let socketPath = "/var/run/ntfs-manager-helper.sock"
    public static let label = "com.leneu.ntfs-manager.helper"

    public init() {}
    public var isHelper: Bool { true }

    /// 헬퍼 데몬이 응답하는지 확인
    public static func ping() -> Bool {
        (try? Self().request(fields: ["PING"]))?.stdout.contains("PONG") == true
    }

    public func run(_ op: PrivilegedOp) throws -> CommandResult {
        try request(fields: Self.encode(op))
    }

    static func encode(_ op: PrivilegedOp) -> [String] {
        switch op {
        case .exec(let path, let args):
            return ["EXEC", path, args.joined(separator: "\u{1E}")]
        case .spawn(let path, let args, let env, let log):
            let envStr = env.map { "\($0.key)=\($0.value)" }.joined(separator: "\u{1E}")
            return ["SPAWN", path, log, envStr, args.joined(separator: "\u{1E}")]
        case .mkdir(let p): return ["MKDIR", p]
        case .rmdir(let p): return ["RMDIR", p]
        case .clearLog(let p): return ["CLEARLOG", p]
        }
    }

    func request(fields: [String]) throws -> CommandResult {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HelperError.unavailable }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            Self.socketPath.withCString { cstr in
                strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cstr, 104)
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard ok == 0 else { throw HelperError.unavailable }

        let req = fields.joined(separator: "\u{1F}").data(using: .utf8)!
        let sent = req.withUnsafeBytes { write(fd, $0.baseAddress, req.count) }
        guard sent == req.count else { throw HelperError.unavailable }
        shutdown(fd, SHUT_WR)

        var res = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            res.append(buf, count: n)
        }
        return try Self.decode(res)
    }

    static func decode(_ data: Data) throws -> CommandResult {
        guard data.count > 5, data.starts(with: Data("EXIT ".utf8)) else {
            throw HelperError.unavailable
        }
        let parts = data[5...].split(separator: 0x1F, maxSplits: 2, omittingEmptySubsequences: false)
        let code = Int32(String(decoding: parts[0], as: UTF8.self).trimmingCharacters(in: .whitespaces)) ?? 1
        let out = parts.count > 1 ? String(decoding: parts[1], as: UTF8.self) : ""
        let err = parts.count > 2 ? String(decoding: parts[2], as: UTF8.self) : ""
        return CommandResult(exitCode: code, stdout: out, stderr: err)
    }
}

// MARK: - osascript 폴백

public final class OsascriptRunner: PrivilegedRunner {
    public init() {}
    public var isHelper: Bool { false }

    static func shq(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// op → POSIX 셸 명령 문자열 (인자는 모두 단일인용 부호로 이스케이프)
    static func shell(for op: PrivilegedOp) -> String {
        switch op {
        case .exec(let path, let args):
            return ([shq(path)] + args.map(shq)).joined(separator: " ")
        case .spawn(let path, let args, let env, let log):
            let envStr = env.map { "\($0.key)=\(shq($0.value))" }.joined(separator: " ")
            let argv = ([shq(path)] + args.map(shq)).joined(separator: " ")
            return "\(envStr) \(argv) </dev/null >\(shq(log)) 2>&1 & echo spawned"
        case .mkdir(let p): return "mkdir -p \(shq(p))"
        case .rmdir(let p): return "rmdir \(shq(p))"
        case .clearLog(let p): return ": > \(shq(p))"
        }
    }

    public func run(_ op: PrivilegedOp) throws -> CommandResult {
        let shellCommand = Self.shell(for: op)
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let res = try CommandRunner.run("/usr/bin/osascript", ["-e", script], timeout: 120)
        // osascript는 스크립트 실패 시 exit 1 + stderr에 "User canceled" 등
        if res.exitCode != 0 {
            if res.stderr.localizedCaseInsensitiveContains("canceled") {
                throw NTFSManagerError.cancelled
            }
            return CommandResult(exitCode: res.exitCode, stdout: res.stdout, stderr: res.stderr)
        }
        return res
    }
}

// MARK: - 자동 선택: 헬퍼가 살아있으면 무비밀번호, 아니면 osascript

public final class AutoRunner: PrivilegedRunner {
    private let helper = HelperRunner()
    private let osascript = OsascriptRunner()

    public init() {}
    public var isHelper: Bool { HelperRunner.ping() }

    public func run(_ op: PrivilegedOp) throws -> CommandResult {
        do {
            return try helper.run(op)
        } catch HelperError.unavailable {
            return try osascript.run(op)
        }
    }
}

// MARK: - 헬퍼 설치

public enum HelperInstaller {
    /// ntfs-helper 바이너리 탐색: 앱 번들 내 sibling → 빌드 디렉토리 → PATH
    public static func binaryPath() -> String? {
        var candidates: [String] = []
        if let exe = Bundle.main.executableURL {
            candidates.append(exe.deletingLastPathComponent().appendingPathComponent("ntfs-helper").path)
        }
        if let argv0 = CommandLine.arguments.first {
            candidates.append(URL(fileURLWithPath: argv0).deletingLastPathComponent()
                .appendingPathComponent("ntfs-helper").path)
        }
        candidates.append(FileManager.default.currentDirectoryPath + "/.build/release/ntfs-helper")
        candidates.append(FileManager.default.currentDirectoryPath + "/.build/debug/ntfs-helper")
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// osascript로 1회 관리자 승인을 받아 헬퍼를 설치/부트스트랩한다.
    public static func install() throws {
        guard let bin = binaryPath() else {
            throw NTFSManagerError.dependencyMissing("ntfs-helper")
        }
        // root 셸은 TCC로 ~/Documents 등 보호 경로를 못 읽으므로 /tmp에 스테이징
        let stage = "/tmp/ntfs-manager-helper"
        let fm = FileManager.default
        try? fm.removeItem(atPath: stage)
        try fm.copyItem(atPath: bin, toPath: stage)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stage)
        let res = try OsascriptRunner().run(.exec(path: stage, args: ["--install"]))
        try? fm.removeItem(atPath: stage)
        guard res.exitCode == 0 else {
            throw NTFSManagerError.mountFailed(res.stderr.isEmpty ? res.stdout : res.stderr)
        }
    }
}
