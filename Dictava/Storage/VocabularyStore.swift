import SwiftUI

struct VocabularyEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var misrecognized: String
    var corrected: String
}

final class VocabularyStore: ObservableObject {
    @Published var entries: [VocabularyEntry] = []

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Dictava", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("vocabulary.json")
    }()

    init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([VocabularyEntry].self, from: data) else {
            return
        }
        entries = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func addEntry(_ entry: VocabularyEntry) {
        entries.append(entry)
        save()
    }

    func removeEntry(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    func updateEntry(_ entry: VocabularyEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            save()
        }
    }
}
