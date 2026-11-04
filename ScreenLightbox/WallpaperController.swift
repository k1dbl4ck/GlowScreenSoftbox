import AppKit

final class WallpaperController {
    private var saved: [CGDirectDisplayID: SavedWallpaper] = [:]
    private var whiteImageURL: URL?

    init() {
        loadPersistedWallpapers()
        if !saved.isEmpty {
            restoreWallpapers()
        }
    }

    deinit {
        restoreWallpapers()
    }

    func applyWhiteWallpapers(to screens: [NSScreen]) {
        let targetIDs = Set(screens.map(\.displayID))
        for screen in NSScreen.screens where !targetIDs.contains(screen.displayID) {
            restoreWallpaper(on: screen)
        }
        persistSavedWallpapers()

        guard !screens.isEmpty else { return }

        do {
            let whiteURL = try ensureWhiteImage()
            whiteImageURL = whiteURL

            for screen in screens {
                let displayID = screen.displayID
                if saved[displayID] == nil {
                    if let currentURL = NSWorkspace.shared.desktopImageURL(for: screen),
                       !isWhiteWallpaper(currentURL) {
                        saved[displayID] = SavedWallpaper(
                            url: currentURL,
                            options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
                        )
                    }
                }

                try NSWorkspace.shared.setDesktopImageURL(
                    whiteURL,
                    for: screen,
                    options: whiteOptions
                )
            }
            persistSavedWallpapers()
        } catch {
            NSLog("Screen Lightbox could not set a white wallpaper: \(error.localizedDescription)")
        }
    }

    func restoreWallpapers() {
        for screen in NSScreen.screens {
            restoreWallpaper(on: screen)
        }
        saved.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.savedWallpapersKey)
    }

    private func restoreWallpaper(on screen: NSScreen) {
        guard let previous = saved.removeValue(forKey: screen.displayID) else { return }
        do {
            try NSWorkspace.shared.setDesktopImageURL(
                previous.url,
                for: screen,
                options: previous.options
            )
        } catch {
            NSLog("Screen Lightbox could not restore wallpaper: \(error.localizedDescription)")
        }
    }

    private static let savedWallpapersKey = "savedWallpapers"

    private var whiteOptions: [NSWorkspace.DesktopImageOptionKey: Any] {
        [
            .allowClipping: true,
            .fillColor: NSColor.white,
            .imageScaling: NSNumber(value: NSImageScaling.scaleAxesIndependently.rawValue)
        ]
    }

    private func isWhiteWallpaper(_ url: URL) -> Bool {
        url.lastPathComponent == "white.png"
    }

    private func persistSavedWallpapers() {
        guard !saved.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.savedWallpapersKey)
            return
        }
        let payload: [[String: Any]] = saved.map { displayID, wallpaper in
            [
                "displayID": displayID,
                "url": wallpaper.url.absoluteString
            ]
        }
        UserDefaults.standard.set(payload, forKey: Self.savedWallpapersKey)
    }

    private func loadPersistedWallpapers() {
        guard saved.isEmpty,
              let payload = UserDefaults.standard.array(forKey: Self.savedWallpapersKey) as? [[String: Any]] else {
            return
        }

        for item in payload {
            guard let displayIDValue = item["displayID"] as? NSNumber,
                  let urlString = item["url"] as? String,
                  let url = URL(string: urlString) else { continue }
            saved[CGDirectDisplayID(truncating: displayIDValue)] = SavedWallpaper(
                url: url,
                options: [:]
            )
        }
    }

    private func ensureWhiteImage() throws -> URL {
        if let whiteImageURL, FileManager.default.fileExists(atPath: whiteImageURL.path) {
            return whiteImageURL
        }

        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("ScreenLightbox", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("white.png")
        if !FileManager.default.fileExists(atPath: url.path) {
            try writeWhitePNG(to: url)
        }
        return url
    }

    private func writeWhitePNG(to url: URL) throws {
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw WallpaperError.couldNotCreateImage
        }
        try png.write(to: url)
    }
}

private struct SavedWallpaper {
    let url: URL
    let options: [NSWorkspace.DesktopImageOptionKey: Any]
}

private enum WallpaperError: LocalizedError {
    case couldNotCreateImage

    var errorDescription: String? {
        "Could not create a white wallpaper image."
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }

    /// Stable across unplug/replug of the same display. Falls back to the
    /// session display ID if CoreGraphics does not provide a UUID.
    var displayUUIDString: String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return "id-\(displayID)"
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
