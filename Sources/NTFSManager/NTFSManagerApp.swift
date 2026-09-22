import SwiftUI

@main
struct NTFSManagerApp: App {
    @StateObject private var store = VolumeStore()

    var body: some Scene {
        WindowGroup("NTFS Manager") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 560, minHeight: 320)
        }
        .defaultSize(width: 640, height: 420)
    }
}
