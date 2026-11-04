# Screen Lightbox

A small macOS menu-bar utility that turns your display(s) into a **softbox**: a white backdrop with an adjustable dim overlay. Use it for nicer lighting in video calls, or turn it on by hand whenever you want a clean, bright wall behind you.

It lives in the menu bar (sun icon). There is no Dock icon.

## For users

### What it does

When the lightbox is **on**:

1. Selected displays’ wallpapers are set to solid white (your previous wallpaper is remembered). With only one display, that display is always used.
2. A click-through dim overlay sits on those desktops so you can control how bright that white field feels.
3. Optionally, apps that are **not** in fullscreen are hidden so they do not sit on top of the white background. Fullscreen apps (your call window) stay put.
4. Optionally, the lightbox turns **on** when a camera starts and **off** when every camera stops (FaceTime, Zoom, Continuity Camera, USB cameras, and so on).

When the lightbox is **off** (or you quit the app), wallpapers are restored and hidden apps are shown again.

### Controls

Open the sun icon in the menu bar:

| Control | What it does |
| --- | --- |
| Main switch | Turns the lightbox on or off |
| Dim Level | How dark the overlay is (5–85%). Lower is brighter white; higher is more muted. Remembered across launches. |
| Screens | Shown only when more than one display is connected. Choose which displays get the softbox. Choices are remembered by display identity, so a dock unplug/replug restores the same set. |
| Hide apps that aren't fullscreen | Hides other regular apps that have windows on a selected display so the white desktop shows through. Apps with a fullscreen window are left alone. |
| Enable when camera starts | Follows camera use automatically. Off by default. |
| Quit Screen Lightbox | Exits and restores wallpapers |

You can still flip the main switch by hand while camera follow is on. The next camera change will take over again.

### Requirements

- macOS 14 or later
- Xcode to build and run (this repo is an `.xcodeproj`, not a signed App Store build)

### Build and run

1. Open `ScreenLightbox.xcodeproj` in Xcode.
2. Select the **ScreenLightbox** scheme.
3. Run.

If `xcodebuild` from Terminal says it only has Command Line Tools, point it at Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

The app does **not** need Accessibility permission. Camera follow uses Core Media I/O to see whether a camera is *running*; it does not capture video, so macOS typically does not show a Camera privacy prompt.

### Quitting

Quit from the menu panel. Wallpapers are restored on a normal quit. If the app is force-quit while the lightbox is on, the next launch restores the saved wallpapers.

---

## For future development (agents and maintainers)

### Intent

Treat this as a **video-call softbox**, not a general night-shift or brightness daemon. The product goals, in order:

1. White field behind the user on the displays they choose (all of them by default).
2. Manual on/off plus automatic on/off from camera activity.
3. Optional: get other windows out of the way of that white field (implemented as **hide**, not yellow-button minimize).
4. Optional: control how bright the field feels (implemented as a **dim overlay**, not hardware display brightness).

If you add hardware brightness (`CoreDisplay` / `IOKit`), say so in the UI. Do not silently replace the overlay.

### Layout

| File | Role |
| --- | --- |
| `ScreenLightbox/ScreenLightboxApp.swift` | SwiftUI `@main` app; `MenuBarExtra` |
| `ScreenLightbox/MenuPanel.swift` | Menu-bar panel UI |
| `ScreenLightbox/OverlayController.swift` | Orchestrates enable state, persistence, camera task, overlay windows, quit cleanup |
| `ScreenLightbox/WallpaperController.swift` | White wallpaper apply/restore; persists previous wallpaper URLs; restores in `deinit` and on next launch if a session died dirty |
| `ScreenLightbox/AppHider.swift` | `NSRunningApplication.hide()` for apps without a fullscreen window (bounds vs `CGDisplayBounds`) |
| `ScreenLightbox.xcodeproj` | App target; SPM dependency **IsCameraOn** (`https://github.com/sindresorhus/is-camera-on`, 3.x) |

Bundle ID: `com.kid.ScreenLightbox`. Deployment target: macOS 14. Sandbox is **off** so wallpaper changes work. `LSUIElement` is **yes** (agent / no Dock icon).

### How enable works

`OverlayController.isEnabled` is the single switch. When it becomes true:

- `WallpaperController.applyWhiteWallpapers()`
- `AppHider.hideAppsWithoutFullscreenWindows()` if that option is on
- Borderless, click-through overlay windows at `.statusBar` level, sized to each **selected** screen’s `visibleFrame` (menu bar and Dock stay clickable). One connected display always counts as selected.

When it becomes false, wallpapers restore and apps unhide.

### Camera follow

Uses `cameraStatusChanges(includeExternal: true)` from IsCameraOn.

- Listener is created/cancelled from `enableOnCameraStart` (not only at launch).
- Default is **off**.
- Setting `isEnabled` only when the value actually changes avoids extra overlay rebuilds.

Do not switch this back to Accessibility-based window minimize. That permission is all-or-nothing and the system copy implies reading other apps’ UI (including Mail). Hide-via-`NSRunningApplication` was an explicit tradeoff: no TCC, but it hides the whole app instead of miniaturizing windows, and mixed fullscreen+windowed apps are skipped so the fullscreen space is not hidden.

### UserDefaults keys

| Key | Meaning |
| --- | --- |
| `dimAmount` | Overlay alpha, clamped 0.05…0.85; default 0.4 |
| `hideNonFullscreenApps` | Hide option (legacy key `minimizeNonFullscreenWindows` is still read if the new key is missing) |
| `enableOnCameraStart` | Camera follow |
| `displayEnabledByUUID` | Per-display on/off, keyed by `CGDisplayCreateUUIDFromDisplayID` (stable across reconnects). Missing keys default to on. |
| `savedWallpapers` | Previous wallpaper URLs per display ID while the lightbox is on |

### Quit / restore

Wallpaper restore must be **synchronous** on `NSApplication.willTerminateNotification` (main queue). Do not wrap it in `Task { @MainActor in … }` — the process can exit before that task runs.

Also restore from `OverlayController` / `WallpaperController` `deinit`. Force quit cannot run those; leftover `savedWallpapers` is applied on the next `WallpaperController.init`.

### What not to reintroduce without a product decision

- Accessibility (`AXUIElement`) to minimize windows
- App sandbox (breaks wallpaper set/restore for user pictures)
- Polling the camera; IsCameraOn already uses property listeners

### Suggested next work (if asked)

- Hardware display brightness vs overlay dim
- Restore hidden apps across force quit (hide list is in-memory only today)
- Launch at login
- Per-display dim amount
- App icon in `Assets.xcassets`
