import SwiftUI
import Yams

struct Snippet: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var trigger: String
    var replacement: String

    enum CodingKeys: String, CodingKey {
        case trigger, replacement
    }

    init(trigger: String, replacement: String) {
        self.trigger = trigger
        self.replacement = replacement
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.trigger = try container.decode(String.self, forKey: .trigger)
        self.replacement = try container.decode(String.self, forKey: .replacement)
    }
}

struct SnippetFile: Codable {
    var snippets: [Snippet]
}

final class SnippetStore: ObservableObject {
    @Published var snippets: [Snippet] = []

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Dictava", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snippets.yml")
    }()

    init() {
        load()
        if snippets.isEmpty {
            loadDefaults()
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let yaml = String(data: data, encoding: .utf8),
              let file = try? YAMLDecoder().decode(SnippetFile.self, from: yaml) else {
            return
        }
        snippets = file.snippets
    }

    func save() {
        let file = SnippetFile(snippets: snippets)
        guard let yaml = try? YAMLEncoder().encode(file) else { return }
        try? yaml.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func addSnippet(_ snippet: Snippet) {
        snippets.append(snippet)
        save()
    }

    func removeSnippet(at offsets: IndexSet) {
        snippets.remove(atOffsets: offsets)
        save()
    }

    func updateSnippet(_ snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
            save()
        }
    }

    private func loadDefaults() {
        snippets = [
            Snippet(trigger: "my email", replacement: "user@example.com"),
            Snippet(trigger: "meeting template", replacement: """
                ## Meeting Notes - {{date}}
                Attendees:
                ### Agenda
                ### Action Items
                """),
            Snippet(trigger: "thanks email", replacement: """
                Thank you for your message. I appreciate you reaching out and will get back to you shortly.

                Best regards
                """),
        ]
        save()
    }
}
