import SwiftUI

final class TranscriptionLogStore: ObservableObject {
    @Published var logs: [TranscriptionLog] = []

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Dictava", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("transcription_logs.json")
    }()

    private lazy var encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private lazy var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([TranscriptionLog].self, from: data) else {
            return
        }
        logs = decoded
    }

    func save() {
        guard let data = try? encoder.encode(logs) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func log(_ entry: TranscriptionLog) {
        logs.append(entry)
        save()
    }

    // MARK: - Queries

    func todayCount() -> Int {
        logs.filter { Calendar.current.isDateInToday($0.timestamp) }.count
    }

    func todayListeningTime() -> TimeInterval {
        logs.filter { Calendar.current.isDateInToday($0.timestamp) }
            .reduce(0) { $0 + $1.duration }
    }

    func weekCount() -> Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return logs.filter { $0.timestamp >= weekAgo }.count
    }

    func weekListeningTime() -> TimeInterval {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return logs.filter { $0.timestamp >= weekAgo }
            .reduce(0) { $0 + $1.duration }
    }

    func weekWordCount() -> Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return logs.filter { $0.timestamp >= weekAgo }
            .reduce(0) { $0 + $1.wordCount }
    }

    func totalCount() -> Int {
        logs.count
    }

    func recentTranscriptions(limit: Int = 3) -> [TranscriptionLog] {
        Array(logs.filter { !$0.wasVoiceCommand && !$0.text.isEmpty }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit))
    }

    func transcriptions(for date: Date) -> [TranscriptionLog] {
        logs.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: date) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func dailyCounts(days: Int = 14) -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<days).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let count = logs.filter { calendar.isDate($0.timestamp, inSameDayAs: date) }.count
            return (date: date, count: count)
        }
    }
}
