import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case speechRecognition
    case snippets
    case history
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .speechRecognition: return "Speech Recognition"
        case .snippets: return "Snippets"
        case .history: return "History"
        case .advanced: return "About & Data"
        }
    }

    var sfSymbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .speechRecognition: return "waveform"
        case .snippets: return "text.badge.plus"
        case .history: return "chart.bar"
        case .advanced: return "slider.horizontal.3"
        }
    }

    var group: SettingsSectionGroup {
        switch self {
        case .general, .appearance, .speechRecognition: return .top
        case .snippets: return .automation
        case .history, .advanced: return .bottom
        }
    }
}

enum SettingsSectionGroup: String, CaseIterable {
    case top
    case automation
    case bottom

    var title: String? {
        switch self {
        case .top, .bottom: return nil
        case .automation: return "AUTOMATION"
        }
    }

    var sections: [SettingsSection] {
        SettingsSection.allCases.filter { $0.group == self }
    }
}

struct SettingsView: View {
    @State private var selectedSection: SettingsSection
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var snippetStore: SnippetStore
    @EnvironmentObject var transcriptionLogStore: TranscriptionLogStore

    init(initialSection: SettingsSection = .general) {
        _selectedSection = State(initialValue: initialSection)
    }

    private var theme: SettingsTheme { .warm }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.windowBackground)
                .id(selectedSection)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: selectedSection)
        }
        .environment(\.settingsTheme, theme)
        .toggleStyle(ShadcnToggleStyle())
        .frame(minWidth: 720, minHeight: 480)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(SettingsSectionGroup.allCases, id: \.self) { group in
                    if let title = group.title {
                        Text(title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.sectionHeader)
                            .tracking(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                    }

                    ForEach(group.sections) { section in
                        sidebarItem(for: section)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
        }
        .background(theme.sidebarBackground)
    }

    @ViewBuilder
    private func sidebarItem(for section: SettingsSection) -> some View {
        let isSelected = selectedSection == section

        HStack(spacing: 8) {
            Image(systemName: section.sfSymbol)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                .frame(width: 20)

            Text(section.title)
                .font(isSelected
                    ? .system(size: 13, weight: .semibold, design: .rounded)
                    : .system(size: 13))
                .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)

            Spacer()

            if section == .snippets && !snippetStore.snippets.isEmpty {
                badgeView("\(snippetStore.snippets.count)", isSelected: isSelected)
            }

            if section == .history {
                let todayCount = transcriptionLogStore.todayCount()
                if todayCount > 0 {
                    badgeView("\(todayCount)", isSelected: isSelected)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: SettingsTheme.radiusMd)
                .fill(isSelected ? theme.cardBackground : Color.clear)
                .shadow(color: isSelected ? theme.shadow : .clear, radius: 2, y: 1)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(theme.controlAccent)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSection = section
        }
        .onHover { hovering in
            if hovering && !isSelected {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func badgeView(_ text: String, isSelected: Bool = false) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(isSelected ? theme.controlAccent : theme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                isSelected
                    ? theme.controlAccent.opacity(0.1)
                    : theme.controlBackground
            )
            .clipShape(Capsule())
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .general:
            GeneralSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .speechRecognition:
            SpeechRecognitionSettingsView()
        case .snippets:
            SnippetSettingsView()
        case .history:
            HistoryView()
        case .advanced:
            AdvancedSettingsView()
        }
    }
}
