import SwiftUI
import Charts

enum HistoryFilter: String, CaseIterable {
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case allTime = "All Time"
    case custom = "Custom"
}

enum ChartScale: String, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
}

enum ChartMetric: String, CaseIterable {
    case dictations = "Dictations"
    case listeningTime = "Listening Time"
}

struct HistoryView: View {
    @EnvironmentObject var transcriptionLogStore: TranscriptionLogStore
    @State private var filter: HistoryFilter = .allTime
    @State private var searchText = ""
    @State private var expandedLogID: UUID?
    @State private var chartScale: ChartScale = .daily
    @State private var chartMetric: ChartMetric = .dictations
    @State private var showDeleteAlert = false
    @State private var logToDelete: TranscriptionLog?
    @State private var showDatePicker = false
    @State private var customFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customTo = Date()

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
        case .custom:
            let endOfToDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customTo)) ?? customTo
            logs = logs.filter { $0.timestamp >= calendar.startOfDay(for: customFrom) && $0.timestamp < endOfToDay }
        }

        if !searchText.isEmpty {
            logs = logs.filter {
                $0.text.localizedCaseInsensitiveContains(searchText) ||
                $0.rawText.localizedCaseInsensitiveContains(searchText)
            }
        }

        return logs
    }

    private var currentStats: PeriodStats {
        transcriptionLogStore.stats(for: filteredLogs)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact stats row
            let stats = currentStats
            HStack(spacing: 6) {
                compactStat("\(stats.count)", label: "dictations", icon: "number", color: .blue)
                compactStat(formatDuration(stats.duration), label: "listening", icon: "timer", color: .green)
                compactStat("\(stats.wordCount)", label: "words", icon: "text.word.spacing", color: .purple)
                compactStat(stats.averageWPM > 0 ? "\(Int(stats.averageWPM))" : "-", label: "wpm", icon: "gauge.medium", color: .teal)
                compactStat("\(transcriptionLogStore.totalCount())", label: "total", icon: "infinity", color: .indigo)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Chart controls + chart
            HStack(spacing: 0) {
                Picker("Scale", selection: $chartScale) {
                    ForEach(ChartScale.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)

                Spacer()

                Picker("Metric", selection: $chartMetric) {
                    ForEach(ChartMetric.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            chartView
                .frame(height: 90)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Divider()

            // Filter + search + export (single row)
            HStack(spacing: 6) {
                Picker("Filter", selection: $filter) {
                    ForEach(HistoryFilter.allCases.filter({ $0 != .custom }), id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 280)

                Button {
                    showDatePicker.toggle()
                } label: {
                    Image(systemName: filter == .custom ? "calendar.circle.fill" : "calendar")
                        .foregroundStyle(filter == .custom ? .blue : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Custom date range")
                .popover(isPresented: $showDatePicker) {
                    dateRangePopover
                }

                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.5))
                .cornerRadius(6)

                exportMenu
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Transcription list — takes all remaining space
            List {
                if filteredLogs.isEmpty {
                    EmptyStateView(
                        icon: "text.bubble",
                        title: "No transcriptions yet",
                        message: "Start dictating to see your history here."
                    )
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
                            },
                            onDelete: {
                                logToDelete = log
                                showDeleteAlert = true
                            }
                        )
                    }
                }
            }
            .layoutPriority(1)
        }
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
        .alert("Delete Transcription", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let log = logToDelete {
                    transcriptionLogStore.deleteLog(log)
                    if expandedLogID == log.id { expandedLogID = nil }
                }
            }
        } message: {
            Text("This transcription will be permanently deleted.")
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartView: some View {
        let data = chartData
        Chart(data, id: \.date) { item in
            BarMark(
                x: .value("Date", item.date, unit: chartUnit),
                y: .value("Value", chartMetric == .dictations ? Double(item.count) : item.duration)
            )
            .foregroundStyle(.blue.gradient)
            .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisValueLabel(format: chartDateFormat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }

    private var chartData: [(date: Date, count: Int, duration: TimeInterval)] {
        switch chartScale {
        case .daily: return transcriptionLogStore.dailyCounts(days: 14)
        case .weekly: return transcriptionLogStore.weeklyCounts(weeks: 8)
        case .monthly: return transcriptionLogStore.monthlyCounts(months: 6)
        }
    }

    private var chartUnit: Calendar.Component {
        switch chartScale {
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        }
    }

    private var chartDateFormat: Date.FormatStyle {
        switch chartScale {
        case .daily: return .dateTime.month(.abbreviated).day()
        case .weekly: return .dateTime.month(.abbreviated).day()
        case .monthly: return .dateTime.month(.abbreviated)
        }
    }

    // MARK: - Compact Stat

    private func compactStat(_ value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(value)
                .font(.callout.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.06))
        .cornerRadius(6)
    }

    // MARK: - Export

    private var exportMenu: some View {
        Menu {
            Button("Export as CSV...") { exportCSV() }
            Button("Export as JSON...") { exportJSON() }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Date Range Popover

    private var dateRangePopover: some View {
        VStack(spacing: 12) {
            Text("Custom Date Range")
                .font(.headline)

            DatePicker("From:", selection: $customFrom, displayedComponents: .date)
            DatePicker("To:", selection: $customTo, displayedComponents: .date)

            HStack {
                Spacer()
                Button("Apply") {
                    filter = .custom
                    showDatePicker = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Export Actions

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "dictava_history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let csv = transcriptionLogStore.exportAsCSV()
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "dictava_history.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let data = transcriptionLogStore.exportAsJSON() {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            let mins = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(mins)m \(secs)s"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}

// MARK: - Transcription Log Row

struct TranscriptionLogRow: View {
    let log: TranscriptionLog
    let isExpanded: Bool
    let onToggle: () -> Void
    var onDelete: (() -> Void)? = nil

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

                        HStack(spacing: 4) {
                            Text("\(String(format: "%.1f", log.duration))s")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.green.opacity(0.1))
                                .cornerRadius(4)

                            Text("\(log.wordCount) words")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.quaternary)
                                .cornerRadius(4)
                        }
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

                        if let onDelete {
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.vertical, 2)
    }
}
