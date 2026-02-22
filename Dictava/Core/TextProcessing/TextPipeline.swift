import Foundation

protocol TextProcessor {
    var name: String { get }
    var isEnabled: Bool { get }
    func process(_ text: String) async -> TextProcessingResult
}

struct TextProcessingResult {
    let text: String
    let command: VoiceCommand?

    init(text: String, command: VoiceCommand? = nil) {
        self.text = text
        self.command = command
    }
}

final class TextPipeline {
    private var processors: [TextProcessor] = []

    func addProcessor(_ processor: TextProcessor) {
        processors.append(processor)
    }

    func process(_ rawText: String) async -> TextProcessingResult {
        var currentText = rawText
        var detectedCommand: VoiceCommand?

        for processor in processors where processor.isEnabled {
            let result = await processor.process(currentText)
            currentText = result.text
            if let command = result.command {
                detectedCommand = command
            }
        }

        return TextProcessingResult(text: currentText, command: detectedCommand)
    }
}
