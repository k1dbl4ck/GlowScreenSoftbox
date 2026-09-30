import AppKit
import Combine
import IsCameraOn

@MainActor
final class OverlayController: ObservableObject {
    @Published var isEnabled = false {
        didSet { syncWindows() }
    }

    @Published var dimAmount: Double {
        didSet {
            UserDefaults.standard.set(dimAmount, forKey: Self.dimAmountKey)
            applyDim()
        }
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
            startCameraMonitor()
        }
    }

    private static let hideNonFullscreenAppsKey = "hideNonFullscreenApps"
    private static let enableOnCameraStartKey = "enableOnCameraStart"
    private static let dimAmountKey = "dimAmount"
    private static let legacyMinimizeKey = "minimizeNonFullscreenWindows"
    private static let defaultDimAmount = 0.4
    private static let dimAmountRange = 0.05...0.85

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

        if UserDefaults.standard.object(forKey: Self.dimAmountKey) != nil {
            dimAmount = Self.clampedDimAmount(UserDefaults.standard.double(forKey: Self.dimAmountKey))
        } else {
            dimAmount = Self.defaultDimAmount
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
            MainActor.assumeIsolated {
                self?.performQuitCleanup()
            }
        }

        startCameraMonitor()
    }

    deinit {
        cameraTask?.cancel()
        wallpaper.restoreWallpapers()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
    }

    private func performQuitCleanup() {
        cameraTask?.cancel()
        appHider.unhide()
        wallpaper.restoreWallpapers()
    }
    
    private func startCameraMonitor() {
        cameraTask?.cancel()
        cameraTask = nil
        guard enableOnCameraStart else { return }

        cameraTask = Task { [weak self] in
            for await isOn in cameraStatusChanges(includeExternal: true) {
                guard let self, !Task.isCancelled else { break }
                if self.isEnabled != isOn {
                    self.isEnabled = isOn
                }
            }
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

    private static func clampedDimAmount(_ value: Double) -> Double {
        min(max(value, dimAmountRange.lowerBound), dimAmountRange.upperBound)
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
