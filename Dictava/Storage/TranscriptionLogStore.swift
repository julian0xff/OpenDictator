import SwiftUI

struct PendingTranscriptionDraft: Codable {
    var timestamp: Date
    var duration: TimeInterval
    var text: String
    var rawText: String
    var modelUsed: String
}

struct PeriodStats {
    let count: Int
    let duration: TimeInterval
    let wordCount: Int
    let averageWPM: Double
    let averageSessionDuration: TimeInterval
}

final class TranscriptionLogStore: ObservableObject {
    @Published var logs: [TranscriptionLog] = []

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Dictava", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("transcription_logs.json")
    }()
    private let draftFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Dictava", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pending_transcription_draft.json")
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
        recoverPendingDraftIfNeeded()
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

    func savePendingDraft(
        text: String,
        rawText: String,
        duration: TimeInterval,
        modelUsed: String
    ) {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedRaw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty || !cleanedRaw.isEmpty else { return }

        let draft = PendingTranscriptionDraft(
            timestamp: Date(),
            duration: duration,
            text: cleanedText,
            rawText: cleanedRaw,
            modelUsed: modelUsed
        )

        guard let data = try? encoder.encode(draft) else { return }
        try? data.write(to: draftFileURL, options: .atomic)
    }

    func clearPendingDraft() {
        try? FileManager.default.removeItem(at: draftFileURL)
    }

    private func recoverPendingDraftIfNeeded() {
        guard let data = try? Data(contentsOf: draftFileURL),
              let draft = try? decoder.decode(PendingTranscriptionDraft.self, from: data) else {
            return
        }

        // Ignore tiny drafts that are likely noise from very short sessions.
        guard draft.text.count >= 8 || draft.rawText.count >= 8 else {
            clearPendingDraft()
            return
        }

        let recovered = TranscriptionLog(
            timestamp: draft.timestamp,
            duration: draft.duration,
            text: draft.text,
            rawText: draft.rawText,
            modelUsed: "\(draft.modelUsed)-recovered"
        )
        logs.append(recovered)
        save()
        clearPendingDraft()
    }

    // MARK: - Deletion

    func deleteLog(_ log: TranscriptionLog) {
        logs.removeAll { $0.id == log.id }
        save()
    }

    func deleteLogs(_ ids: Set<UUID>) {
        logs.removeAll { ids.contains($0.id) }
        save()
    }

    func deleteAllLogs() {
        logs.removeAll()
        save()
    }

    // MARK: - Basic Queries

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

    func totalListeningTime() -> TimeInterval {
        logs.reduce(0) { $0 + $1.duration }
    }

    func totalWordCount() -> Int {
        logs.reduce(0) { $0 + $1.wordCount }
    }

    func recentTranscriptions(limit: Int = 3) -> [TranscriptionLog] {
        Array(logs.filter { !$0.text.isEmpty }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit))
    }

    func transcriptions(for date: Date) -> [TranscriptionLog] {
        logs.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: date) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Aggregate Stats

    func stats(for filteredLogs: [TranscriptionLog]) -> PeriodStats {
        let count = filteredLogs.count
        let duration = filteredLogs.reduce(0.0) { $0 + $1.duration }
        let wordCount = filteredLogs.reduce(0) { $0 + $1.wordCount }

        let avgWPM: Double
        if duration > 0 {
            avgWPM = Double(wordCount) / (duration / 60.0)
        } else {
            avgWPM = 0
        }

        let avgSessionDuration = count > 0 ? duration / Double(count) : 0

        return PeriodStats(
            count: count,
            duration: duration,
            wordCount: wordCount,
            averageWPM: avgWPM,
            averageSessionDuration: avgSessionDuration
        )
    }

    // MARK: - Chart Data

    func dailyCounts(days: Int = 14) -> [(date: Date, count: Int, duration: TimeInterval)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<days).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let dayLogs = logs.filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
            let count = dayLogs.count
            let duration = dayLogs.reduce(0.0) { $0 + $1.duration }
            return (date: date, count: count, duration: duration)
        }
    }

    func weeklyCounts(weeks: Int = 8) -> [(date: Date, count: Int, duration: TimeInterval)] {
        let calendar = Calendar.current
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!

        return (0..<weeks).reversed().map { offset in
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: -offset, to: endOfToday)!
            let weekStart = calendar.date(byAdding: .day, value: -7, to: weekEnd)!
            let weekLogs = logs.filter { $0.timestamp >= weekStart && $0.timestamp < weekEnd }
            return (date: weekStart, count: weekLogs.count, duration: weekLogs.reduce(0.0) { $0 + $1.duration })
        }
    }

    func monthlyCounts(months: Int = 6) -> [(date: Date, count: Int, duration: TimeInterval)] {
        let calendar = Calendar.current
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!

        return (0..<months).reversed().map { offset in
            let monthEnd = calendar.date(byAdding: .month, value: -offset, to: endOfToday)!
            let monthStart = calendar.date(byAdding: .month, value: -1, to: monthEnd)!
            let monthLogs = logs.filter { $0.timestamp >= monthStart && $0.timestamp < monthEnd }
            return (date: monthStart, count: monthLogs.count, duration: monthLogs.reduce(0.0) { $0 + $1.duration })
        }
    }

    // MARK: - Export

    func exportAsCSV() -> String {
        var csv = "Timestamp,Duration (s),Text,Raw Text,Words,Characters,Model\n"
        let sortedLogs = logs.sorted { $0.timestamp > $1.timestamp }
        let formatter = ISO8601DateFormatter()

        for log in sortedLogs {
            let text = csvEscape(log.text)
            let rawText = csvEscape(log.rawText)
            let model = csvEscape(log.modelUsed)
            csv += "\(formatter.string(from: log.timestamp)),\(String(format: "%.1f", log.duration)),\"\(text)\",\"\(rawText)\",\(log.wordCount),\(log.characterCount),\"\(model)\"\n"
        }
        return csv
    }

    private func csvEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\"", with: "\"\"")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    func exportAsJSON() -> Data? {
        let exportEncoder = JSONEncoder()
        exportEncoder.dateEncodingStrategy = .iso8601
        exportEncoder.outputFormatting = .prettyPrinted
        return try? exportEncoder.encode(logs.sorted { $0.timestamp > $1.timestamp })
    }
}
