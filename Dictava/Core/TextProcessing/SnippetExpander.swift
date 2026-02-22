import Foundation
import AppKit

final class SnippetExpander: TextProcessor {
    let name = "Snippet Expander"
    var isEnabled = true

    private let snippetStore: SnippetStore

    init(snippetStore: SnippetStore) {
        self.snippetStore = snippetStore
    }

    func process(_ text: String) async -> TextProcessingResult {
        var result = text

        for snippet in snippetStore.snippets {
            if let range = result.range(of: snippet.trigger, options: .caseInsensitive) {
                let expanded = expandTemplateVariables(snippet.replacement)
                result.replaceSubrange(range, with: expanded)
            }
        }

        return TextProcessingResult(text: result)
    }

    private func expandTemplateVariables(_ text: String) -> String {
        var result = text
        let now = Date()

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        result = result.replacingOccurrences(of: "{{date}}", with: dateFormatter.string(from: now))

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        result = result.replacingOccurrences(of: "{{time}}", with: timeFormatter.string(from: now))

        if result.contains("{{clipboard}}") {
            let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
            result = result.replacingOccurrences(of: "{{clipboard}}", with: clipboard)
        }

        return result
    }
}
