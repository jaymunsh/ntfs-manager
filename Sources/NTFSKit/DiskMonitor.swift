import Foundation
import DiskArbitration

/// NTFS 볼륨 목록을 수집하고 디스크 연결/제거 이벤트를 감지한다.
public final class DiskMonitor {
    public var onChange: (() -> Void)?

    private var session: DASession?
    private var volumes: [Volume] = []

    public init() {}

    public func start() {
        guard session == nil else { return }
        session = DASessionCreate(kCFAllocatorDefault)
        guard let session else { return }
        DASessionSetDispatchQueue(session, .main)

        DARegisterDiskAppearedCallback(session, nil, { disk, ctx in
            guard let ctx else { return }
            Unmanaged<DiskMonitor>.fromOpaque(ctx).takeUnretainedValue().onChange?()
        }, Unmanaged.passUnretained(self).toOpaque())
        DARegisterDiskDisappearedCallback(session, nil, { disk, ctx in
            guard let ctx else { return }
            Unmanaged<DiskMonitor>.fromOpaque(ctx).takeUnretainedValue().onChange?()
        }, Unmanaged.passUnretained(self).toOpaque())
        DARegisterDiskDescriptionChangedCallback(session, nil, nil, { disk, keys, ctx in
            guard let ctx else { return }
            Unmanaged<DiskMonitor>.fromOpaque(ctx).takeUnretainedValue().onChange?()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    /// diskutil로 NTFS 파티션을 찾아 마운트 상태를 붙인다.
    public func scan() -> [Volume] {
        guard let data = try? CommandRunner.run("/usr/sbin/diskutil",
                                                ["list", "-plist"]).stdout.data(using: .utf8),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let all = root["AllDisksAndPartitions"] as? [[String: Any]] else {
            return []
        }

        var result: [Volume] = []
        for disk in all {
            guard let partitions = disk["Partitions"] as? [[String: Any]] else { continue }
            for part in partitions {
                // GPT NTFS: Content="Microsoft Basic Data" / MBR NTFS: "Windows_NTFS"
                // 실제 파일시스템 판별은 diskutil info의 FilesystemType=="ntfs"로 한다
                guard let content = part["Content"] as? String,
                      Self.ntfsCandidateContents.contains(content),
                      let ident = part["DeviceIdentifier"] as? String,
                      let info = Self.diskInfo(ident),
                      (info["FilesystemType"] as? String) == "ntfs" else { continue }

                let name = info["VolumeName"] as? String ?? ""
                let size = part["Size"] as? Int64 ?? 0
                let mountPoint = info["MountPoint"] as? String ?? ""
                let removable = (disk["Internal"] as? Bool) == false

                var v = Volume(
                    id: ident,
                    name: name,
                    devicePath: "/dev/\(ident)",
                    size: size,
                    mountState: mountPoint.isEmpty ? .unmounted : .nativeReadOnly(mountPoint: mountPoint),
                    isRemovable: removable,
                    dirty: false)

                // 네이티브 마운트가 없는데 ntfs-3g 프로세스가 이 장치를 잡고 있으면 FUSE-T RW 마운트
                if mountPoint.isEmpty,
                   let fusetMP = Self.fuseTMountPoint(for: ident) {
                    v.mountState = .fuseTReadWrite(mountPoint: fusetMP)
                }
                result.append(v)
            }
        }
        volumes = result
        return result
    }

    /// NTFS일 수 있는 파티션 Content 타입 (MBR/GPT 모두 커버)
    static let ntfsCandidateContents: Set<String> = [
        "Windows_NTFS", "Microsoft Basic Data", "Windows_Recovery", "Windows_LDM-metadata",
    ]

    static func diskInfo(_ ident: String) -> [String: Any]? {
        guard let res = try? CommandRunner.run("/usr/sbin/diskutil",
                                               ["info", "-plist", "/dev/\(ident)"]),
              res.exitCode == 0,
              let dict = try? PropertyListSerialization.propertyList(
                  from: res.stdout.data(using: .utf8)!, format: nil) as? [String: Any]
        else { return nil }
        return dict
    }

    /// fuse-t(NFS loopback) 마운트 테이블에서 ntfs-3g가 잡은 마운트포인트를 찾는다.
    static func fuseTMountPoint(for deviceId: String) -> String? {
        // ntfs-3g 프로세스 명령행에서 마운트포인트를 얻는다: "ntfs-3g /dev/diskXsY /Volumes/NAME -o ..."
        guard let res = try? CommandRunner.run("/usr/bin/pgrep", ["-fl", "ntfs-3g"]),
              res.exitCode == 0 else { return nil }
        for line in res.stdout.split(separator: "\n") {
            // "ntfs-3g /dev/diskXsY /Volumes/My Passport -o ..." — 마운트포인트에 공백이
            // 있을 수 있으므로 디바이스 경로 뒤부터 " -o" 앞까지를 통째로 취한다
            guard let devRange = line.range(of: "/dev/\(deviceId) ") else { continue }
            let rest = line[devRange.upperBound...]
            let mp = rest.range(of: " -o").map { String(rest[..<$0.lowerBound]) }
                ?? String(rest)
            let trimmed = mp.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
