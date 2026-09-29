import AppKit
import CoreGraphics

@MainActor
final class AppHider {
    private var hiddenApps: [NSRunningApplication] = []

    func hideAppsWithoutFullscreenWindows() {
        let fullscreenPIDs = Self.pidsOwningFullscreenWindows()
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let alreadyHidden = Set(hiddenApps.map(\.processIdentifier))

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            guard app.processIdentifier != selfPID else { continue }
            guard !app.isTerminated else { continue }
            guard !alreadyHidden.contains(app.processIdentifier) else { continue }
            guard !app.isHidden else { continue }
            guard !fullscreenPIDs.contains(app.processIdentifier) else { continue }
            if app.hide() {
                hiddenApps.append(app)
            }
        }
    }

    func unhide() {
        for app in hiddenApps where !app.isTerminated {
            app.unhide()
        }
        hiddenApps.removeAll()
    }

    private static func pidsOwningFullscreenWindows() -> Set<pid_t> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let displayBounds = NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        var pids = Set<pid_t>()

        for window in info {
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            guard let pidNumber = window[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let pid = pid_t(truncating: pidNumber)
            guard let bounds = cgRect(from: window[kCGWindowBounds as String]) else { continue }
            if displayBounds.contains(where: { framesMatch(bounds, $0) }) {
                pids.insert(pid)
            }
        }

        return pids
    }

    private static func cgRect(from value: Any?) -> CGRect? {
        guard let dictionary = value as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dictionary)
    }

    private static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 2
            && abs(lhs.minY - rhs.minY) < 2
            && abs(lhs.width - rhs.width) < 2
            && abs(lhs.height - rhs.height) < 2
    }
}
