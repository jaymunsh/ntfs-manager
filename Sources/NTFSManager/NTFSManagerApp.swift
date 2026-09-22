import SwiftUI

@main
struct NTFSManagerApp: App {
    @StateObject private var store = VolumeStore()

    var body: some Scene {
        WindowGroup("NTFS Manager") {
            ContentView()
                .environmentObject(store)
                .frame(width: 620, height: 320)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
