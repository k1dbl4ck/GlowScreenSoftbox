import SwiftUI

@main
struct ScreenLightboxApp: App {
    @StateObject private var overlay = OverlayController()

    var body: some Scene {
        MenuBarExtra("Screen Lightbox", systemImage: overlay.isEnabled ? "sun.max.fill" : "sun.max") {
            MenuPanel()
                .environmentObject(overlay)
        }
        .menuBarExtraStyle(.window)
    }
}
