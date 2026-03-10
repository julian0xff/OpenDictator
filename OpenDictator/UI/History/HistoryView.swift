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

// MARK: - History View

struct HistoryView: View {
    @EnvironmentObject var transcriptionLogStore: TranscriptionLogStore
    @Environment(\.settingsTheme) private var theme
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
            // Analytics header
            VStack(spacing: 16) {
                statsGrid
                chartSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            // Filter and search toolbar
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Picker("Filter", selection: $filter) {
                        ForEach(HistoryFilter.allCases.filter({ $0 != .custom }), id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Button {
                        showDatePicker.toggle()
                    } label: {
                        Image(systemName: filter == .custom ? "calendar.circle.fill" : "calendar")
                            .font(.body)
                            .foregroundStyle(filter == .custom ? theme.controlAccent : theme.textTertiary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Custom date range")
                    .popover(isPresented: $showDatePicker) {
                        dateRangePopover
                    }
                }

                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(theme.textTertiary)
                            .font(.callout)
                        TextField("Search transcriptions...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.callout)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(theme.textSecondary)
                                    .font(.callout)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.cardBackground)
                    .cornerRadius(SettingsTheme.radiusLg)
                    .overlay(
                        RoundedRectangle(cornerRadius: SettingsTheme.radiusLg)
                            .stroke(theme.border, lineWidth: 1)
                    )

                    exportMenu
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            // Transcription list
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
            .listStyle(.plain)
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

    // MARK: - Stats Grid

    private var statsGrid: some View {
        let stats = currentStats
        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            HistoryStatCard(label: "Sessions", value: stats.count.formatted(), icon: "number")
            HistoryStatCard(label: "Listening Time", value: formatDuration(stats.duration), icon: "timer")
            HistoryStatCard(label: "Words", value: stats.wordCount.formatted(), icon: "text.word.spacing")
            HistoryStatCard(
                label: "Avg Speed",
                value: stats.averageWPM > 0 ? "\(Int(stats.averageWPM)) wpm" : "\u{2014}",
                icon: "gauge.medium"
            )
        }
    }

    // MARK: - Chart Section

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Period", selection: $chartScale) {
                ForEach(ChartScale.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 240)

            ZStack(alignment: .topTrailing) {
                chartView
                    .frame(height: 140)
                    .animation(.easeInOut(duration: 0.3), value: chartScale)
                    .animation(.easeInOut(duration: 0.3), value: chartMetric)
                    .padding(.top, 8)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                Menu {
                    ForEach(ChartMetric.allCases, id: \.self) { m in
                        Button(m.rawValue) { chartMetric = m }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(chartMetric.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(theme.textSecondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(theme.textTertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.controlBackground, in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(8)
            }
            .background(theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.radiusXl))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsTheme.radiusXl)
                    .stroke(theme.border, lineWidth: 1)
            )
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
            .foregroundStyle(theme.controlAccent.gradient)
            .cornerRadius(4)
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

    // MARK: - Export

    private var exportMenu: some View {
        Menu {
            Button("Export as CSV...") { exportCSV() }
            Button("Export as JSON...") { exportJSON() }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.callout)
                .foregroundStyle(theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Date Range Popover

    private var dateRangePopover: some View {
        VStack(spacing: 16) {
            Text("Custom Date Range")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)

            DatePicker("From:", selection: $customFrom, displayedComponents: .date)
            DatePicker("To:", selection: $customTo, displayedComponents: .date)

            HStack {
                Spacer()
                Button("Apply") {
                    filter = .custom
                    showDatePicker = false
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 300)
    }

    // MARK: - Export Actions

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "opendictator_history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let csv = transcriptionLogStore.exportAsCSV()
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "opendictator_history.json"
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

// MARK: - Stat Card

private struct HistoryStatCard: View {
    let label: String
    let value: String
    let icon: String
    @Environment(\.settingsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(theme.controlAccent.opacity(0.7))
                Text(label.uppercased())
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.3)
            }

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.radiusLg))
        .shadow(color: theme.shadow, radius: 3, y: 1)
    }
}

// MARK: - Transcription Log Row

struct TranscriptionLogRow: View {
    let log: TranscriptionLog
    let isExpanded: Bool
    let onToggle: () -> Void
    var onDelete: (() -> Void)? = nil
    @Environment(\.settingsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(formatTimestamp(log.timestamp))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(theme.textPrimary)

                        Spacer()

                        HStack(spacing: 6) {
                            badge("\(String(format: "%.1f", log.duration))s")
                            badge("\(log.wordCount) words")
                        }

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(theme.textTertiary)
                    }

                    Text(log.text.isEmpty ? "(empty)" : log.text)
                        .lineLimit(isExpanded ? nil : 2)
                        .font(.callout)
                        .foregroundStyle(log.text.isEmpty ? theme.textTertiary : theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(2)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if log.rawText != log.text && !log.rawText.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Raw transcription")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(theme.textTertiary)
                            Text(log.rawText)
                                .font(.callout)
                                .foregroundStyle(theme.textSecondary)
                                .lineSpacing(2)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(theme.controlBackground)
                                .cornerRadius(SettingsTheme.radiusLg)
                        }
                    }

                    HStack(spacing: 16) {
                        Label("\(String(format: "%.1f", log.duration))s", systemImage: "timer")
                        Label(log.modelUsed, systemImage: "cpu")
                        Label("\(log.characterCount) chars", systemImage: "character.cursor.ibeam")
                    }
                    .font(.caption)
                    .foregroundStyle(theme.textTertiary)

                    HStack {
                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(log.text, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.callout)
                        }
                        .buttonStyle(GhostButtonStyle())

                        if let onDelete {
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .font(.callout)
                            }
                            .buttonStyle(DestructiveButtonStyle())
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(theme.controlBackground, in: Capsule())
    }

    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today, " + date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday, " + date.formatted(date: .omitted, time: .shortened)
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
    }
}
