import AppKit

extension NSScreen {
    /// Stable display identifier, usable as a dictionary key for per-screen storage.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Returns the screen that currently contains the mouse cursor.
    /// Falls back safely when the cursor position cannot be matched.
    static var focused: NSScreen {
        let allScreens = NSScreen.screens
        guard let fallbackScreen = NSScreen.main ?? allScreens.first else {
            preconditionFailure("NSScreen.focused requested with no available screens")
        }

        let mouseLocation = NSEvent.mouseLocation
        if let pointerScreen = allScreens.first(where: { $0.frame.contains(mouseLocation) }) {
            return pointerScreen
        }

        return fallbackScreen
    }

    /// Whether this screen has a physical notch (MacBook Pro 2021+).
    /// Uses auxiliary areas which only exist on notched displays,
    /// regardless of menu bar visibility or safe area inset quirks.
    var hasNotch: Bool {
        auxiliaryTopLeftArea != nil && auxiliaryTopRightArea != nil
    }

    /// Height of the notch area (menu bar safe area inset).
    /// Falls back to frame-based calculation when safeAreaInsets.top is 0
    /// (can happen with auto-hide menu bar).
    var notchHeight: CGFloat {
        if safeAreaInsets.top > 0 {
            return safeAreaInsets.top
        }
        // Fallback: distance from top of frame to top of visible frame
        let fallback = frame.maxY - visibleFrame.maxY
        return fallback > 0 ? fallback : 0
    }

    /// Width of the physical notch, or nil on screens without one.
    var notchWidth: CGFloat? {
        guard hasNotch,
              let leftArea = auxiliaryTopLeftArea,
              let rightArea = auxiliaryTopRightArea else {
            return nil
        }
        return frame.width - leftArea.width - rightArea.width + 10
    }
}
