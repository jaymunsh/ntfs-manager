import SwiftUI
import NTFSKit

struct ContentView: View {
    @EnvironmentObject var store: VolumeStore
    @State private var showSetup = false

    var body: some View {
        VStack(spacing: 0) {
            if !store.deps.ready {
                SetupBanner(showSetup: $showSetup)
            }

            if store.volumes.isEmpty {
                ContentUnavailableView(
                    "NTFS 드라이브 없음",
                    systemImage: "externaldrive",
                    description: Text("NTFS로 포맷된 드라이브를 연결하면 여기에 표시됩니다."))
            } else {
                List(store.volumes) { v in
                    VolumeRowView(volume: v)
                }
            }

            if let err = store.lastError {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text("백엔드: ntfs-3g + FUSE-T")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("새로고침") { store.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .sheet(isPresented: $showSetup) { SetupGuideView() }
    }
}

struct SetupBanner: View {
    @Binding var showSetup: Bool

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("쓰기 지원 구성요소가 설치되지 않았습니다.")
            Spacer()
            Button("설치 가이드") { showSetup = true }
        }
        .padding(10)
        .background(.yellow.opacity(0.12))
    }
}
