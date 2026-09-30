import AppKit
import Combine
import IsCameraOn

@MainActor
final class OverlayController: ObservableObject {
    @Published var isEnabled = false {
        didSet { syncWindows() }
    }

    @Published var dimAmount: Double = 0.4 {
        didSet { applyDim() }
    }

    @Published var hideNonFullscreenApps: Bool {
        didSet {
            UserDefaults.standard.set(hideNonFullscreenApps, forKey: Self.hideNonFullscreenAppsKey)
            syncHiddenApps()
        }
    }
    
    @Published var enableOnCameraStart: Bool {
        didSet {
            UserDefaults.standard.set(enableOnCameraStart, forKey: Self.enableOnCameraStartKey)
        }
    }

    private static let hideNonFullscreenAppsKey = "hideNonFullscreenApps"
    private static let enableOnCameraStartKey = "enableOnCameraStart"
    private static let legacyMinimizeKey = "minimizeNonFullscreenWindows"

    private var windows: [NSWindow] = []
    private var screenObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var cameraTask: Task<Void, Never>?
    private let wallpaper = WallpaperController()
    private let appHider = AppHider()

    init() {
        
        if UserDefaults.standard.object(forKey: Self.hideNonFullscreenAppsKey) != nil {
            hideNonFullscreenApps = UserDefaults.standard.bool(forKey: Self.hideNonFullscreenAppsKey)
        } else {
            hideNonFullscreenApps = UserDefaults.standard.bool(forKey: Self.legacyMinimizeKey)
        }
        
        if UserDefaults.standard.object(forKey: Self.enableOnCameraStartKey) != nil {
            enableOnCameraStart = UserDefaults.standard.bool(forKey: Self.enableOnCameraStartKey)
        } else {
            enableOnCameraStart = false
        }
        
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncWindows()
            }
        }

        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.cameraTask?.cancel()
                self.appHider.unhide()
                self.wallpaper.restoreWallpapers()
            }
        }

        startCameraMonitor()
    }

    deinit {
        cameraTask?.cancel()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
    }
    
    private func startCameraMonitor() {
        if enableOnCameraStart {
            cameraTask = Task { [weak self] in
                for await isOn in cameraStatusChanges(includeExternal: true) {
                    guard let self, !Task.isCancelled else { break }
                    if self.isEnabled != isOn {
                        self.isEnabled = isOn
                    }
                }
            }
        } else {
            cameraTask?.cancel()
        }
    }

    private func syncWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        syncWallpaper()
        syncHiddenApps()

        guard isEnabled else { return }

        for screen in NSScreen.screens {
            let window = makeOverlay(on: screen)
            windows.append(window)
            window.orderFrontRegardless()
        }
    }

    private func syncHiddenApps() {
        if isEnabled, hideNonFullscreenApps {
            appHider.hideAppsWithoutFullscreenWindows()
        } else {
            appHider.unhide()
        }
    }

    private func syncWallpaper() {
        if isEnabled {
            wallpaper.applyWhiteWallpapers()
        } else {
            wallpaper.restoreWallpapers()
        }
    }

    private func applyDim() {
        for window in windows {
            window.backgroundColor = NSColor.black.withAlphaComponent(dimAmount)
        }
    }

    private func makeOverlay(on screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.visibleFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor.black.withAlphaComponent(dimAmount)
        window.setFrame(screen.visibleFrame, display: true)
        return window
    }
}
