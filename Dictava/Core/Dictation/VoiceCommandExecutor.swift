import CoreGraphics
import AppKit

final class VoiceCommandExecutor {
    func execute(_ command: VoiceCommand) async {
        switch command {
        case .deleteThat, .undoThat:
            simulateKeyCombo(key: 0x07, modifiers: .maskCommand) // Cmd+Z
        case .selectAll:
            simulateKeyCombo(key: 0x00, modifiers: .maskCommand) // Cmd+A
        case .newLine:
            simulateKey(key: 0x24) // Return
        case .newParagraph:
            simulateKey(key: 0x24) // Return
            try? await Task.sleep(nanoseconds: 50_000_000)
            simulateKey(key: 0x24) // Return
        case .stopListening:
            break // Handled by DictationSession
        case .llmRewrite:
            break // Handled by LLMProcessor in Phase 6
        }
    }

    private func simulateKeyCombo(key: CGKeyCode, modifiers: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }

        keyDown.flags = modifiers
        keyUp.flags = modifiers

        SyntheticEventMarker.mark(keyDown)
        SyntheticEventMarker.mark(keyUp)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func simulateKey(key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }

        SyntheticEventMarker.mark(keyDown)
        SyntheticEventMarker.mark(keyUp)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
