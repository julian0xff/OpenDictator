import AppKit
import CoreGraphics

/// Manages a CGEventTap that intercepts a configurable key for hold-to-record functionality.
/// When the configured key is held down, dictation starts. When released, dictation stops.
/// The key event is consumed (not passed to other apps) while hold-to-record is active.
final class HoldToRecordManager {
    /// Singleton reference for the C callback to access the current instance.
    /// Set when the event tap starts, cleared when it stops.
    static var current: HoldToRecordManager?

    // MARK: - Configuration

    /// Whether hold-to-record is active. When false, the event tap passes all events through.
    var isEnabled: Bool = false

    /// The virtual key code to use for hold-to-record. Default: 0x0A (§ key on ISO keyboards).
    var configuredKeyCode: Int64 = 0x0A

    /// When true, the event tap passes all events through without consuming.
    /// Used during key capture in the settings UI.
    var isCapturingKey: Bool = false

    // MARK: - Callbacks

    /// Called on the main queue when the hold key is initially pressed (not on repeat).
    var onStartDictation: (() -> Void)?

    /// Called on the main queue when the hold key is released.
    var onStopDictation: (() -> Void)?

    // MARK: - State

    /// Whether the current dictation session was initiated by hold-to-record.
    /// Used to prevent releasing the hold key from stopping a toggle-initiated session.
    var holdSessionActive: Bool = false

    /// Whether the event tap is currently active and intercepting events.
    var isTapActive: Bool { eventTap != nil }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyHeld: Bool = false

    // MARK: - Lifecycle

    /// Creates the CGEventTap and adds it to the main run loop.
    /// Requires Accessibility permission. No-op if already started.
    /// Returns true if the tap was created successfully.
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        // Try session-level tap first, fall back to HID-level tap
        let tap: CFMachPort? = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: holdToRecordEventTapCallback,
            userInfo: nil
        )

        guard let tap else {
            let axTrusted = AXIsProcessTrusted()
            NSLog("HoldToRecord: CGEvent.tapCreate failed (AXIsProcessTrusted=%d). Accessibility permission may not be granted for this build.", axTrusted ? 1 : 0)
            return false
        }

        HoldToRecordManager.current = self
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("HoldToRecord: Event tap created successfully (keyCode=%lld)", configuredKeyCode)
        return true
    }

    /// Destroys the CGEventTap and cleans up. If a hold session is active, releases it first.
    func stop() {
        if holdSessionActive {
            holdSessionActive = false
            DispatchQueue.main.async { [weak self] in
                self?.onStopDictation?()
            }
        }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isKeyHeld = false
        HoldToRecordManager.current = nil
    }

    // MARK: - Event Handling

    fileprivate static func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        guard let manager = current else {
            return Unmanaged.passUnretained(event)
        }

        // Re-enable tap if the system disabled it (e.g. callback took too long)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            NSLog("HoldToRecord: Tap was disabled by system, re-enabling")
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Pass through if disabled or in key capture mode for settings
        guard manager.isEnabled, !manager.isCapturingKey else {
            return Unmanaged.passUnretained(event)
        }

        // Don't intercept our own synthetic events from TextInjector
        if SyntheticEventMarker.isSynthetic(event) {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == manager.configuredKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if type == .keyDown {
            if !isRepeat && !manager.isKeyHeld {
                manager.isKeyHeld = true
                DispatchQueue.main.async {
                    manager.onStartDictation?()
                }
            }
            return nil // Consume the event (including repeats)
        } else if type == .keyUp {
            manager.isKeyHeld = false
            DispatchQueue.main.async {
                manager.onStopDictation?()
            }
            return nil // Consume
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Key Display Names

    /// Returns a human-readable name for a virtual key code.
    static func displayName(for keyCode: Int64) -> String {
        let knownKeys: [Int64: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0A: "§", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E",
            0x0F: "R", 0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2",
            0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
            0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
            0x1E: "]", 0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I",
            0x23: "P", 0x24: "↩", 0x25: "L", 0x26: "J", 0x27: "'",
            0x28: "K", 0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/",
            0x2D: "N", 0x2E: "M", 0x2F: ".", 0x30: "⇥",
            0x31: "Space", 0x32: "`", 0x33: "⌫", 0x35: "⎋",
            // F-keys
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
            0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
            0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
            0x69: "F13", 0x6B: "F14", 0x71: "F15",
            // Arrow keys
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        ]
        return knownKeys[keyCode] ?? "Key \(keyCode)"
    }

    /// Key codes that should not be assignable as hold keys (modifier keys).
    static let excludedKeyCodes: Set<Int64> = [
        0x37, 0x36, // Left/Right Command
        0x38, 0x3C, // Left/Right Shift
        0x3A, 0x3D, // Left/Right Option
        0x3B, 0x3E, // Left/Right Control
        0x39,       // Caps Lock
        0x3F,       // Function (fn)
    ]
}

/// Top-level C callback for CGEventTap. Must be a non-capturing function.
private func holdToRecordEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    HoldToRecordManager.handleEvent(proxy: proxy, type: type, event: event)
}
