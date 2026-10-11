import SwiftUI

@main
struct RaspberryApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 820)
        #endif
    }
}
