import Foundation

final class CustomVocabulary: TextProcessor {
    let name = "Custom Vocabulary"
    var isEnabled = true

    private let vocabularyStore: VocabularyStore

    init(vocabularyStore: VocabularyStore) {
        self.vocabularyStore = vocabularyStore
    }

    func process(_ text: String) async -> TextProcessingResult {
        var result = text

        for entry in vocabularyStore.entries {
            if let regex = try? NSRegularExpression(
                pattern: "\\b\(NSRegularExpression.escapedPattern(for: entry.misrecognized))\\b",
                options: .caseInsensitive
            ) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: entry.corrected
                )
            }
        }

        return TextProcessingResult(text: result)
    }
}
