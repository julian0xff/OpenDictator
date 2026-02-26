import Foundation

final class SentenceCapitalizer: TextProcessor {
    let name = "Sentence Capitalizer"
    private let settingsStore: SettingsStore
    var isEnabled: Bool { settingsStore.autoCapitalize }

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func process(_ text: String) async -> TextProcessingResult {
        var result = text

        // Capitalize first letter
        if let first = result.first, first.isLetter && first.isLowercase {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }

        // Capitalize first letter after sentence-ending punctuation followed by whitespace
        let pattern = "([.!?])\\s+(\\p{Ll})"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsString = result as NSString
            var offset = 0
            regex.enumerateMatches(in: result, range: NSRange(location: 0, length: nsString.length)) { match, _, _ in
                guard let match, match.numberOfRanges == 3 else { return }
                let letterRange = match.range(at: 2)
                let adjustedRange = NSRange(location: letterRange.location + offset, length: letterRange.length)
                let mutable = NSMutableString(string: result)
                let lowercase = mutable.substring(with: adjustedRange)
                let uppercased = lowercase.uppercased()
                mutable.replaceCharacters(in: adjustedRange, with: uppercased)
                let lengthDiff = uppercased.count - lowercase.count
                result = mutable as String
                offset += lengthDiff
            }
        }

        return TextProcessingResult(text: result)
    }
}
