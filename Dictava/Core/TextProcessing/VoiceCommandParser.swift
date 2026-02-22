import Foundation

enum VoiceCommand: Equatable {
    case deleteThat
    case undoThat
    case selectAll
    case newLine
    case newParagraph
    case stopListening
    case llmRewrite(style: LLMRewriteStyle)

    enum LLMRewriteStyle: String, Equatable {
        case shorter = "make it shorter"
        case formal = "make it formal"
        case casual = "make it casual"
        case fixGrammar = "fix grammar"
    }

    var logName: String {
        switch self {
        case .deleteThat: return "deleteThat"
        case .undoThat: return "undoThat"
        case .selectAll: return "selectAll"
        case .newLine: return "newLine"
        case .newParagraph: return "newParagraph"
        case .stopListening: return "stopListening"
        case .llmRewrite(let style): return "llmRewrite.\(style.rawValue)"
        }
    }
}

struct VoiceCommandDefinition {
    let name: String
    let triggers: [String]
    let command: VoiceCommand
    let actionDescription: String
}

final class VoiceCommandParser: TextProcessor {
    let name = "Voice Command Parser"
    var isEnabled = true

    private let settingsStore: SettingsStore

    static let allDefinitions: [VoiceCommandDefinition] = [
        VoiceCommandDefinition(name: "deleteThat", triggers: ["delete that", "scratch that"], command: .deleteThat, actionDescription: "Undo (Cmd+Z)"),
        VoiceCommandDefinition(name: "undoThat", triggers: ["undo that", "undo"], command: .undoThat, actionDescription: "Undo (Cmd+Z)"),
        VoiceCommandDefinition(name: "selectAll", triggers: ["select all"], command: .selectAll, actionDescription: "Select All (Cmd+A)"),
        VoiceCommandDefinition(name: "newLine", triggers: ["new line"], command: .newLine, actionDescription: "Insert line break"),
        VoiceCommandDefinition(name: "newParagraph", triggers: ["new paragraph"], command: .newParagraph, actionDescription: "Insert double line break"),
        VoiceCommandDefinition(name: "stopListening", triggers: ["stop listening", "stop dictation"], command: .stopListening, actionDescription: "End dictation session"),
        VoiceCommandDefinition(name: "llmRewrite.shorter", triggers: ["make it shorter"], command: .llmRewrite(style: .shorter), actionDescription: "LLM rewrite (shorter)"),
        VoiceCommandDefinition(name: "llmRewrite.formal", triggers: ["make it formal"], command: .llmRewrite(style: .formal), actionDescription: "LLM tone shift (formal)"),
        VoiceCommandDefinition(name: "llmRewrite.casual", triggers: ["make it casual"], command: .llmRewrite(style: .casual), actionDescription: "LLM tone shift (casual)"),
        VoiceCommandDefinition(name: "llmRewrite.fixGrammar", triggers: ["fix grammar", "fix the grammar"], command: .llmRewrite(style: .fixGrammar), actionDescription: "LLM grammar cleanup"),
    ]

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func process(_ text: String) async -> TextProcessingResult {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        for definition in Self.allDefinitions {
            guard settingsStore.isVoiceCommandEnabled(definition.name) else { continue }

            for trigger in definition.triggers {
                if lowered.hasSuffix(trigger) {
                    // Remove the command from the text
                    let commandRange = lowered.range(of: trigger, options: .backwards)!
                    let startIndex = text.index(text.startIndex, offsetBy: lowered.distance(from: lowered.startIndex, to: commandRange.lowerBound))
                    let remainingText = String(text[text.startIndex..<startIndex])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return TextProcessingResult(text: remainingText, command: definition.command)
                }

                if lowered == trigger {
                    return TextProcessingResult(text: "", command: definition.command)
                }
            }
        }

        return TextProcessingResult(text: text)
    }
}
