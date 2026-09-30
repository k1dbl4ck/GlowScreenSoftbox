import AppKit

@MainActor
final class WallpaperController {
    private var saved: [CGDirectDisplayID: SavedWallpaper] = [:]
    private var whiteImageURL: URL?
    
    func applyWhiteWallpapers() {
        do {
            let whiteURL = try ensureWhiteImage()
            whiteImageURL = whiteURL

            for screen in NSScreen.screens {
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
        } catch {
            NSLog("Screen Lightbox could not set a white wallpaper: \(error.localizedDescription)")
        }
    }

    func restoreWallpapers() {
        for screen in NSScreen.screens {
            guard let previous = saved[screen.displayID] else { continue }
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
        saved.removeAll()
    }

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
}
