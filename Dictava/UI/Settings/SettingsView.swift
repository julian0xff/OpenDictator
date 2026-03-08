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
    @Environment(\.colorScheme) private var colorScheme

    init(initialSection: SettingsSection = .general) {
        _selectedSection = State(initialValue: initialSection)
    }

    private var theme: SettingsTheme {
        .resolve(colorScheme: colorScheme, appearance: settingsStore.settingsAppearance)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)

            Rectangle()
                .fill(theme.border)
                .frame(width: 1)

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
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SettingsSectionGroup.allCases, id: \.self) { group in
                        if let title = group.title {
                            Text(title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.textTertiary)
                                .tracking(0.5)
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

            Spacer()

            // Appearance picker
            appearancePicker
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
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
                .font(.callout)
                .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)

            Spacer()

            if section == .snippets && !snippetStore.snippets.isEmpty {
                badgeView("\(snippetStore.snippets.count)")
            }

            if section == .history {
                let todayCount = transcriptionLogStore.todayCount()
                if todayCount > 0 {
                    badgeView("\(todayCount)")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: SettingsTheme.radiusMd)
                .fill(isSelected ? theme.cardBackground : Color.clear)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1)
                    .fill(theme.controlAccent)
                    .frame(width: 2)
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

    private func badgeView(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(theme.controlBackground)
            .clipShape(Capsule())
    }

    // MARK: - Appearance Picker

    private var appearancePicker: some View {
        HStack(spacing: 0) {
            ForEach(SettingsAppearance.allCases, id: \.self) { mode in
                let isActive = settingsStore.settingsAppearance == mode

                Button {
                    settingsStore.settingsAppearance = mode
                } label: {
                    Image(systemName: iconForAppearance(mode))
                        .font(.system(size: 12))
                        .foregroundStyle(isActive ? theme.textPrimary : theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: SettingsTheme.radiusSm)
                                .fill(isActive ? theme.cardBackground : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: SettingsTheme.radiusMd)
                .fill(theme.controlBackground)
        )
    }

    private func iconForAppearance(_ mode: SettingsAppearance) -> String {
        switch mode {
        case .light: return "sun.max"
        case .system: return "desktopcomputer"
        case .dark: return "moon"
        }
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
