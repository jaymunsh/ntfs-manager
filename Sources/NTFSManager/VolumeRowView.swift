import SwiftUI
import NTFSKit

struct VolumeRowView: View {
    @EnvironmentObject var store: VolumeStore
    let volume: Volume

    var busy: Bool { store.busyVolumeIDs.contains(volume.id) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.fill")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(volume.displayName).font(.headline)
                    stateBadge
                }
                Text("\(volume.id) · \(Self.formatSize(volume.size))")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if busy {
                ProgressView().controlSize(.small)
            } else {
                actions
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder var stateBadge: some View {
        switch volume.mountState {
        case .fuseTReadWrite(let mp):
            Label(L("읽기/쓰기"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.caption)
                .help(mp)
        case .nativeReadOnly(let mp):
            Label(L("읽기 전용 (macOS)"), systemImage: "lock.fill")
                .foregroundStyle(.orange).font(.caption)
                .help(mp)
        case .unmounted:
            Text(L("언마운트됨")).font(.caption).foregroundStyle(.secondary)
        case .busy:
            Text(L("작업 중")).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder var actions: some View {
        switch volume.mountState {
        case .nativeReadOnly:
            Button(L("읽기/쓰기로 마운트")) { store.mountRW(volume) }
                .buttonStyle(.borderedProminent)
            Button(L("언마운트")) { store.unmount(volume) }
            Button(L("제거")) { store.eject(volume) }
        case .fuseTReadWrite(let mp):
            Button("Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: mp)) }
            Button(L("언마운트")) { store.unmount(volume) }
            Button(L("제거")) { store.eject(volume) }
        case .unmounted:
            Button(L("읽기/쓰기")) { store.mountRW(volume) }
                .buttonStyle(.borderedProminent)
            Button(L("읽기전용")) { store.mountRO(volume) }
            Button(L("복구")) { store.repair(volume) }
            Button(L("제거")) { store.eject(volume) }
        case .busy:
            EmptyView()
        }
    }

    static func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
