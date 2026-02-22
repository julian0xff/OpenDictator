import SwiftUI
import Charts

enum HistoryFilter: String, CaseIterable {
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case allTime = "All Time"
}

struct HistoryView: View {
    @EnvironmentObject var transcriptionLogStore: TranscriptionLogStore
    @State private var filter: HistoryFilter = .allTime
    @State private var searchText = ""
    @State private var expandedLogID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Stats dashboard
            HStack(spacing: 16) {
                StatCard(title: "Today", value: "\(transcriptionLogStore.todayCount())", subtitle: "dictations")
                StatCard(title: "Today", value: formatDuration(transcriptionLogStore.todayListeningTime()), subtitle: "listening")
                StatCard(title: "All Time", value: "\(transcriptionLogStore.totalCount())", subtitle: "total")
            }
            .padding()

            // Bar chart
            let dailyCounts = transcriptionLogStore.dailyCounts(days: 14)
            Chart(dailyCounts, id: \.date) { item in
                BarMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(.blue.gradient)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 120)
            .padding(.horizontal)
            .padding(.bottom)

            Divider()

            // Filter bar
            Picker("Filter", selection: $filter) {
                ForEach(HistoryFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Transcription list
            List {
                if filteredLogs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("No transcriptions yet")
                            .foregroundStyle(.secondary)
                        Text("Start dictating to see your history here.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredLogs) { log in
                        TranscriptionLogRow(
                            log: log,
                            isExpanded: expandedLogID == log.id,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedLogID = expandedLogID == log.id ? nil : log.id
                                }
                            }
                        )
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search transcriptions")
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var filteredLogs: [TranscriptionLog] {
        let calendar = Calendar.current
        let now = Date()

        var logs = transcriptionLogStore.logs
            .sorted { $0.timestamp > $1.timestamp }

        switch filter {
        case .today:
            logs = logs.filter { calendar.isDateInToday($0.timestamp) }
        case .thisWeek:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            logs = logs.filter { $0.timestamp >= weekAgo }
        case .thisMonth:
            let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            logs = logs.filter { $0.timestamp >= monthAgo }
        case .allTime:
            break
        }

        if !searchText.isEmpty {
            logs = logs.filter {
                $0.text.localizedCaseInsensitiveContains(searchText) ||
                $0.rawText.localizedCaseInsensitiveContains(searchText)
            }
        }

        return logs
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(8)
    }
}

struct TranscriptionLogRow: View {
    let log: TranscriptionLog
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Collapsed view
            Button(action: onToggle) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        if log.wasVoiceCommand {
                            HStack(spacing: 4) {
                                Image(systemName: "command")
                                    .font(.caption2)
                                Text(log.voiceCommandName ?? "Command")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(.orange)
                        }

                        Text(log.text.isEmpty ? "(empty)" : log.text)
                            .lineLimit(isExpanded ? nil : 2)
                            .foregroundStyle(log.text.isEmpty ? .tertiary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(log.timestamp, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(log.wordCount) words")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .cornerRadius(4)
                    }
                }
            }
            .buttonStyle(.plain)

            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if log.rawText != log.text && !log.rawText.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Raw transcription")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(log.rawText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.5))
                                .cornerRadius(4)
                        }
                    }

                    HStack(spacing: 12) {
                        Label("\(String(format: "%.1f", log.duration))s", systemImage: "timer")
                        Label(log.modelUsed, systemImage: "cpu")
                        Label("\(log.characterCount) chars", systemImage: "character.cursor.ibeam")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                    HStack {
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(log.text, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.vertical, 2)
    }
}
