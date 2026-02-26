import Foundation

struct TranscriptionLog: Identifiable, Codable, Equatable {
    var id: UUID
    var timestamp: Date
    var duration: TimeInterval
    var text: String
    var rawText: String
    var wordCount: Int
    var characterCount: Int
    var modelUsed: String

    init(
        timestamp: Date = Date(),
        duration: TimeInterval,
        text: String,
        rawText: String,
        modelUsed: String
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.duration = duration
        self.text = text
        self.rawText = rawText
        self.wordCount = text.split(separator: " ").count
        self.characterCount = text.count
        self.modelUsed = modelUsed
    }
}
