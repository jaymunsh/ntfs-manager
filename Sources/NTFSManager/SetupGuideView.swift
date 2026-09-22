import SwiftUI
import NTFSKit

struct SetupGuideView: View {
    @EnvironmentObject var store: VolumeStore
    @Environment(\.dismiss) private var dismiss
    @State private var installing = false
    @State private var installOutput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("쓰기 지원 설치")
                .font(.title2).bold()

            Text("NTFS 쓰기에는 두 구성요소가 필요합니다:")
                .font(.callout)

            DepRow(name: "FUSE-T", desc: "커널 확장 없는 FUSE (kextless)",
                   ok: store.deps.fuseT)
            DepRow(name: "ntfs-3g", desc: "NTFS 읽기/쓰기 드라이버 (FUSE-T 빌드)",
                   ok: store.deps.ntfs3g != nil)

            Divider()

            Text("터미널에서 직접 설치:")
                .font(.callout).bold()
            CodeBlock("brew install --cask fuse-t\n" +
                      "brew tap <github-user>/ntfs-manager\n" +
                      "brew install ntfs-3g-fuset")

            Text("또는 앱에서 자동 설치:")
                .font(.callout).bold()
            Button(installing ? "설치 중…" : "자동 설치 실행") {
                runInstaller()
            }
            .disabled(installing)

            if !installOutput.isEmpty {
                ScrollView {
                    Text(installOutput).font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .background(.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Spacer()
                Button("닫기") { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    func runInstaller() {
        installing = true
        installOutput = ""
        Task.detached {
            let script = Bundle.main.path(forResource: "install-deps", ofType: "sh")
                ?? "\(FileManager.default.currentDirectoryPath)/Scripts/install-deps.sh"
            let res = try? CommandRunner.run("/bin/bash", [script], timeout: 1800)
            await MainActor.run {
                installing = false
                installOutput = ((res?.stdout ?? "") + "\n" + (res?.stderr ?? ""))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                store.refresh()
            }
        }
    }
}

struct DepRow: View {
    let name: String
    let desc: String
    let ok: Bool

    var body: some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .red)
            VStack(alignment: .leading) {
                Text(name).bold()
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ok ? "설치됨" : "미설치").font(.caption)
                .foregroundStyle(ok ? .green : .red)
        }
    }
}

struct CodeBlock: View {
    let text: String
    init(_ t: String) { text = t }

    var body: some View {
        Text(text)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
