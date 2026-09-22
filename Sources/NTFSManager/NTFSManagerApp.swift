import SwiftUI

@main
struct NTFSManagerApp: App {
    @StateObject private var store = VolumeStore()

    var body: some Scene {
        WindowGroup("NTFS Manager") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 560, minHeight: 200)
        }
        .defaultSize(width: 620, height: 320)
    }
}
