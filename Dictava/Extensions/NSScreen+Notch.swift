import AppKit

extension NSScreen {
    /// Stable display identifier, usable as a dictionary key for per-screen storage.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// The screen the user is currently focused on (contains the key window).
    /// Falls back to primary screen if no key window exists.
    static var focused: NSScreen {
        NSScreen.main ?? NSScreen.screens.first!
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
