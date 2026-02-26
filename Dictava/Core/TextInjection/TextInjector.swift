import AppKit
import CoreGraphics

actor TextInjector {
    /// Tracks what text has actually been injected by partial updates.
    /// Managed internally so the diff is always against actual screen state.
    private var lastPartialText = ""

    /// Resets partial tracking state. Call at the start/end of each dictation session.
    func resetPartialTracking() {
        lastPartialText = ""
    }

    /// Injects text at the current cursor position in any app.
    /// Strategy: Save clipboard -> Set text -> Simulate Cmd+V -> Restore clipboard
    func inject(_ text: String) async {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let savedItems = savePasteboard(pasteboard)

        // Set our text on the clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure pasteboard is ready
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Simulate Cmd+V
        simulatePaste()

        // Wait for paste to complete, then restore clipboard
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        restorePasteboard(pasteboard, items: savedItems)
    }

    /// Injects partial text inline using diff-based updates.
    /// Only deletes and retypes the changed suffix, avoiding full-text flicker.
    /// Tracks injected state internally — caller just provides the new text.
    func injectPartial(_ newText: String) async {
        // NFC normalize to avoid commonPrefix mismatches across normalization forms
        let prev = lastPartialText.precomposedStringWithCanonicalMapping
        let next = newText.precomposedStringWithCanonicalMapping
        let commonPrefix = prev.commonPrefix(with: next)
        let charsToDelete = prev.count - commonPrefix.count
        let newSuffix = String(next.dropFirst(commonPrefix.count))

        // Delete the changed tail of the previous text
        if charsToDelete > 0 {
            sendBackspaces(count: charsToDelete)
            try? await Task.sleep(nanoseconds: 30_000_000) // 30ms for backspaces to register
            if Task.isCancelled {
                // Backspaces already sent — screen now shows just the common prefix
                lastPartialText = String(prev.prefix(commonPrefix.count))
                return
            }
        }

        // After backspaces, screen shows the common prefix
        lastPartialText = String(next.prefix(commonPrefix.count))

        guard !newSuffix.isEmpty else { return }
        guard !Task.isCancelled else { return }

        // Short text: type character-by-character (no clipboard clobber, no paste flash)
        if newSuffix.count < 50 {
            typeString(newSuffix)
        } else {
            // Long text: fall back to clipboard paste
            let pasteboard = NSPasteboard.general
            let savedItems = savePasteboard(pasteboard)

            pasteboard.clearContents()
            pasteboard.setString(newSuffix, forType: .string)

            try? await Task.sleep(nanoseconds: 30_000_000) // 30ms
            if Task.isCancelled {
                restorePasteboard(pasteboard, items: savedItems)
                return
            }
            simulatePaste()
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

            restorePasteboard(pasteboard, items: savedItems)
        }

        lastPartialText = newText
    }

    // MARK: - Private Helpers

    private func sendBackspaces(count: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<count {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)
            else { continue }
            SyntheticEventMarker.mark(keyDown)
            SyntheticEventMarker.mark(keyUp)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// Types a string character-by-character using CGEvent Unicode input.
    /// Avoids clipboard usage entirely — ideal for short real-time partial updates.
    private func typeString(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for char in text {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }
            let utf16 = Array(String(char).utf16)
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            SyntheticEventMarker.mark(keyDown)
            SyntheticEventMarker.mark(keyUp)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true), // V key
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        SyntheticEventMarker.mark(keyDown)
        SyntheticEventMarker.mark(keyUp)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func savePasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType: Data] {
        var saved: [NSPasteboard.PasteboardType: Data] = [:]

        for item in pasteboard.pasteboardItems ?? [] {
            for type in item.types {
                if let data = item.data(forType: type) {
                    saved[type] = data
                }
            }
        }

        return saved
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, items: [NSPasteboard.PasteboardType: Data]) {
        pasteboard.clearContents()

        if items.isEmpty { return }

        let item = NSPasteboardItem()
        for (type, data) in items {
            item.setData(data, forType: type)
        }
        pasteboard.writeObjects([item])
    }
}
