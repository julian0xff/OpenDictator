import Foundation

enum VoiceCommand: Equatable {
    case deleteThat
    case undoThat
    case selectAll
    case newLine
    case newParagraph
    case stopListening
    case llmRewrite(style: LLMRewriteStyle)
    case customTextReplacement(text: String)

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
        case .customTextReplacement: return "customTextReplacement"
        }
    }
}

struct VoiceCommandDefinition {
    let name: String
    let triggers: [String]
    let command: VoiceCommand
    let actionDescription: String
    let category: CommandCategory
}

final class VoiceCommandParser: TextProcessor {
    let name = "Voice Command Parser"
    var isEnabled = true

    private let settingsStore: SettingsStore
    private let customVoiceCommandStore: CustomVoiceCommandStore?

    static let allDefinitions: [VoiceCommandDefinition] = [
        VoiceCommandDefinition(name: "deleteThat", triggers: ["delete that", "scratch that"], command: .deleteThat, actionDescription: "Undo (Cmd+Z)", category: .editing),
        VoiceCommandDefinition(name: "undoThat", triggers: ["undo that", "undo"], command: .undoThat, actionDescription: "Undo (Cmd+Z)", category: .editing),
        VoiceCommandDefinition(name: "selectAll", triggers: ["select all"], command: .selectAll, actionDescription: "Select All (Cmd+A)", category: .editing),
        VoiceCommandDefinition(name: "newLine", triggers: ["new line"], command: .newLine, actionDescription: "Insert line break", category: .formatting),
        VoiceCommandDefinition(name: "newParagraph", triggers: ["new paragraph"], command: .newParagraph, actionDescription: "Insert double line break", category: .formatting),
        VoiceCommandDefinition(name: "stopListening", triggers: ["stop listening", "stop dictation"], command: .stopListening, actionDescription: "End dictation session", category: .session),
        VoiceCommandDefinition(name: "llmRewrite.shorter", triggers: ["make it shorter"], command: .llmRewrite(style: .shorter), actionDescription: "LLM rewrite (shorter)", category: .ai),
        VoiceCommandDefinition(name: "llmRewrite.formal", triggers: ["make it formal"], command: .llmRewrite(style: .formal), actionDescription: "LLM tone shift (formal)", category: .ai),
        VoiceCommandDefinition(name: "llmRewrite.casual", triggers: ["make it casual"], command: .llmRewrite(style: .casual), actionDescription: "LLM tone shift (casual)", category: .ai),
        VoiceCommandDefinition(name: "llmRewrite.fixGrammar", triggers: ["fix grammar", "fix the grammar"], command: .llmRewrite(style: .fixGrammar), actionDescription: "LLM grammar cleanup", category: .ai),
    ]

    init(settingsStore: SettingsStore, customVoiceCommandStore: CustomVoiceCommandStore? = nil) {
        self.settingsStore = settingsStore
        self.customVoiceCommandStore = customVoiceCommandStore
    }

    func process(_ text: String) async -> TextProcessingResult {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Check built-in commands
        for definition in Self.allDefinitions {
            guard settingsStore.isVoiceCommandEnabled(definition.name) else { continue }

            let triggers = settingsStore.effectiveTriggers(for: definition.name, defaults: definition.triggers)
            for trigger in triggers {
                if lowered == trigger {
                    return TextProcessingResult(text: "", command: definition.command)
                } else if lowered.hasSuffix(trigger) {
                    let commandRange = lowered.range(of: trigger, options: .backwards)!
                    let startIndex = text.index(text.startIndex, offsetBy: lowered.distance(from: lowered.startIndex, to: commandRange.lowerBound))
                    let remainingText = String(text[text.startIndex..<startIndex])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return TextProcessingResult(text: remainingText, command: definition.command)
                }
            }
        }

        // Check custom commands — snapshot to avoid data race
        let customCommands = customVoiceCommandStore?.commands ?? []
        for custom in customCommands where custom.isEnabled {
            for trigger in custom.triggers {
                let triggerLower = trigger.lowercased()
                if lowered == triggerLower {
                    return TextProcessingResult(text: custom.replacementText, command: .customTextReplacement(text: custom.replacementText))
                } else if lowered.hasSuffix(triggerLower) {
                    let commandRange = lowered.range(of: triggerLower, options: .backwards)!
                    let startIndex = text.index(text.startIndex, offsetBy: lowered.distance(from: lowered.startIndex, to: commandRange.lowerBound))
                    let remainingText = String(text[text.startIndex..<startIndex])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let fullText = remainingText.isEmpty ? custom.replacementText : remainingText + " " + custom.replacementText
                    return TextProcessingResult(text: fullText, command: .customTextReplacement(text: custom.replacementText))
                }
            }
        }

        return TextProcessingResult(text: text)
    }
}
