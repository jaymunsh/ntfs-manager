import Foundation

/// root 권한이 필요한 명령을 실행하는 추상화.
/// MVP는 osascript(관리자 권한 프롬프트), 이후 launchd 데몬 헬퍼로 교체 예정.
public protocol PrivilegedRunner: Sendable {
    func runAsRoot(_ shellCommand: String) throws -> CommandResult
}

public final class OsascriptRunner: PrivilegedRunner {
    public init() {}

    public func runAsRoot(_ shellCommand: String) throws -> CommandResult {
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
