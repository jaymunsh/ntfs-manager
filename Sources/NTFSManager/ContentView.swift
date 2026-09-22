import SwiftUI
import NTFSKit

struct ContentView: View {
    @EnvironmentObject var store: VolumeStore
    @State private var showSetup = false
    @AppStorage("autoMountRW") private var autoMount = false

    var body: some View {
        VStack(spacing: 0) {
            if !store.deps.ready {
                SetupBanner(showSetup: $showSetup)
            }

            if store.volumes.isEmpty {
                ContentUnavailableView {
                    Label(L("NTFS 드라이브 없음"), systemImage: "externaldrive")
                } description: {
                    Text(L("NTFS로 포맷된 드라이브를 연결하면 여기에 표시됩니다."))
                }
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
            } else if let info = store.lastInfo {
                Text(info)
                    .font(.callout)
                    .foregroundStyle(.green)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text(L("백엔드: ntfs-3g + FUSE-T"))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(L("자동 마운트"), isOn: $autoMount)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help(Text(L("NTFS 드라이브 연결 시 자동으로 읽기/쓰기 마운트")))
                Picker(selection: $store.appLanguage) {
                    Text("Auto").tag("")
                    Text("한국어").tag("ko")
                    Text("English").tag("en")
                } label: {
                    Image(systemName: "globe")
                }
                .pickerStyle(.menu)
                .fixedSize()
                Spacer()
                Button(L("디스크 권한 설정")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
                Button(L("새로고침")) { store.refresh() }
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
            Text(L("쓰기 지원 구성요소가 설치되지 않았습니다."))
            Spacer()
            Button(L("설치 가이드")) { showSetup = true }
        }
        .padding(10)
        .background(.yellow.opacity(0.12))
    }
}
