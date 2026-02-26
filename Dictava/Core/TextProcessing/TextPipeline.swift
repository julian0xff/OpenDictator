import Foundation

protocol TextProcessor {
    var name: String { get }
    var isEnabled: Bool { get }
    func process(_ text: String) async -> TextProcessingResult
}

struct TextProcessingResult {
    let text: String
}

final class TextPipeline {
    private var processors: [TextProcessor] = []

    func addProcessor(_ processor: TextProcessor) {
        processors.append(processor)
    }

    func process(_ rawText: String) async -> TextProcessingResult {
        var currentText = rawText

        for processor in processors where processor.isEnabled {
            let result = await processor.process(currentText)
            currentText = result.text
        }

        return TextProcessingResult(text: currentText)
    }
}
