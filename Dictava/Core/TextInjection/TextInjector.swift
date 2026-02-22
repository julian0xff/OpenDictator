import AppKit
import CoreGraphics

final class TextInjector {
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
