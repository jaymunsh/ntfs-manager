import Foundation

public enum MountState: Equatable, Sendable {
    case nativeReadOnly(mountPoint: String)   // macOS 내장 NTFS (읽기 전용)
    case fuseTReadWrite(mountPoint: String)   // ntfs-3g + FUSE-T (읽기/쓰기)
    case unmounted
    case busy
}

public struct Volume: Identifiable, Equatable, Sendable {
    public let id: String            // DeviceIdentifier, e.g. "disk4s2"
    public var name: String
    public var devicePath: String    // /dev/disk4s2
    public var size: Int64
    public var mountState: MountState
    public var isRemovable: Bool
    public var dirty: Bool           // hibernated/needs-chkdsk 추정

    public var displayName: String {
        name.isEmpty ? id : name
    }
}

public enum NTFSManagerError: Error, Equatable, Sendable {
    case dependencyMissing(String)
    case unmountFailed(String)
    case mountFailed(String)
    case hibernated
    case needsRepair
    case cancelled
}
