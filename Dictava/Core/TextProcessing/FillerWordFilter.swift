import Foundation

final class FillerWordFilter: TextProcessor {
    let name = "Filler Word Filter"
    var isEnabled = true

    private let fillerPatterns: [String] = [
        "\\bum\\b",
        "\\buh\\b",
        "\\buhh\\b",
        "\\bumm\\b",
        "\\ber\\b",
        "\\berm\\b",
        "\\bahh?\\b",
        "\\blike\\b(?=\\s+(basically|so|you know|I mean))",
        "\\byou know\\b",
        "\\bI mean\\b",
        "\\bbasically\\b",
        "\\bso\\b(?=\\s+(like|basically|um|uh))",
        "\\bkind of\\b",
        "\\bsort of\\b",
    ]

    // Conservative set - only remove the most obvious fillers
    private let strictFillerPatterns: [String] = [
        "\\bum\\b",
        "\\buh\\b",
        "\\buhh\\b",
        "\\bumm\\b",
        "\\ber\\b",
        "\\berm\\b",
        "\\bahh?\\b",
    ]

    func process(_ text: String) async -> TextProcessingResult {
        var result = text

        for pattern in strictFillerPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Clean up double spaces left behind
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return TextProcessingResult(text: result)
    }
}
