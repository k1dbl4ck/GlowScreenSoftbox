import AppKit
import Combine
import IsCameraOn

struct DisplayChoice: Identifiable, Equatable {
    var id: String { uuid }
    let uuid: String
    let name: String
    var isEnabled: Bool
}

@MainActor
final class OverlayController: ObservableObject {
    @Published var isEnabled = false {
        didSet { syncWindows() }
    }

    @Published private(set) var connectedDisplays: [DisplayChoice] = []

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
    private static let displayEnabledByUUIDKey = "displayEnabledByUUID"
    private static let legacyMinimizeKey = "minimizeNonFullscreenWindows"
    private static let defaultDimAmount = 0.4
    private static let dimAmountRange = 0.05...0.85

    var showsDisplayPicker: Bool {
        connectedDisplays.count > 1
    }

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
                self?.refreshDisplays()
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

        refreshDisplays()
        startCameraMonitor()
    }

    func setDisplayEnabled(_ uuid: String, _ enabled: Bool) {
        var prefs = displayEnabledPrefs()
        prefs[uuid] = enabled
        UserDefaults.standard.set(prefs, forKey: Self.displayEnabledByUUIDKey)
        if let index = connectedDisplays.firstIndex(where: { $0.uuid == uuid }) {
            connectedDisplays[index].isEnabled = enabled
        }
        syncWindows()
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

    private func refreshDisplays() {
        let prefs = displayEnabledPrefs()
        connectedDisplays = NSScreen.screens.map { screen in
            let uuid = screen.displayUUIDString
            return DisplayChoice(
                uuid: uuid,
                name: screen.localizedName,
                isEnabled: prefs[uuid] ?? true
            )
        }
    }

    /// With one display, always use it. With several, honor remembered checkboxes.
    private var targetScreens: [NSScreen] {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return screens }
        let enabledUUIDs = Set(connectedDisplays.filter(\.isEnabled).map(\.uuid))
        return screens.filter { enabledUUIDs.contains($0.displayUUIDString) }
    }

    private func displayEnabledPrefs() -> [String: Bool] {
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.displayEnabledByUUIDKey) else {
            return [:]
        }
        var prefs: [String: Bool] = [:]
        for (key, value) in raw {
            if let flag = value as? Bool {
                prefs[key] = flag
            } else if let number = value as? NSNumber {
                prefs[key] = number.boolValue
            }
        }
        return prefs
    }

    private func syncWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        syncWallpaper()
        syncHiddenApps()

        guard isEnabled else { return }

        for screen in targetScreens {
            let window = makeOverlay(on: screen)
            windows.append(window)
            window.orderFrontRegardless()
        }
    }

    private func syncHiddenApps() {
        if isEnabled, hideNonFullscreenApps {
            appHider.hideAppsWithoutFullscreenWindows(on: targetScreens.map(\.displayID))
        } else {
            appHider.unhide()
        }
    }

    private func syncWallpaper() {
        if isEnabled {
            wallpaper.applyWhiteWallpapers(to: targetScreens)
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
