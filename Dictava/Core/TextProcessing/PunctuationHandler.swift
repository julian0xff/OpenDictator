import Foundation

final class PunctuationHandler: TextProcessor {
    let name = "Punctuation Handler"
    var isEnabled = true

    private let replacements: [(pattern: String, replacement: String)] = [
        ("\\bperiod\\b", "."),
        ("\\bfull stop\\b", "."),
        ("\\bcomma\\b", ","),
        ("\\bquestion mark\\b", "?"),
        ("\\bexclamation mark\\b", "!"),
        ("\\bexclamation point\\b", "!"),
        ("\\bcolon\\b", ":"),
        ("\\bsemicolon\\b", ";"),
        ("\\bdash\\b", "—"),
        ("\\bhyphen\\b", "-"),
        ("\\bellipsis\\b", "…"),
        ("\\bopen quote\\b", "\""),
        ("\\bclose quote\\b", "\""),
        ("\\bopen paren\\b", "("),
        ("\\bclose paren\\b", ")"),
        ("\\bopen bracket\\b", "["),
        ("\\bclose bracket\\b", "]"),
    ]

    func process(_ text: String) async -> TextProcessingResult {
        var result = text

        for (pattern, replacement) in replacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: replacement
                )
            }
        }

        // Clean up spaces before punctuation: "hello ." -> "hello."
        result = result.replacingOccurrences(of: " .", with: ".")
        result = result.replacingOccurrences(of: " ,", with: ",")
        result = result.replacingOccurrences(of: " ?", with: "?")
        result = result.replacingOccurrences(of: " !", with: "!")
        result = result.replacingOccurrences(of: " :", with: ":")
        result = result.replacingOccurrences(of: " ;", with: ";")

        return TextProcessingResult(text: result)
    }
}
