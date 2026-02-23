import SwiftUI
import PhosphorSwift

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case speechRecognition
    case textProcessing
    case snippets
    case commands
    case history
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .speechRecognition: return "Speech Recognition"
        case .textProcessing: return "Text Processing"
        case .snippets: return "Snippets"
        case .commands: return "Commands"
        case .history: return "History"
        case .advanced: return "Advanced"
        }
    }

    var icon: Image {
        switch self {
        case .general: return Ph.gear.duotone
        case .appearance: return Ph.palette.duotone
        case .speechRecognition: return Ph.waveform.duotone
        case .textProcessing: return Ph.textAa.duotone
        case .snippets: return Ph.notePencil.duotone
        case .commands: return Ph.command.duotone
        case .history: return Ph.chartBar.duotone
        case .advanced: return Ph.faders.duotone
        }
    }

    var group: SettingsSectionGroup {
        switch self {
        case .general, .appearance: return .top
        case .speechRecognition, .textProcessing: return .speechAndText
        case .snippets, .commands: return .automation
        case .history, .advanced: return .bottom
        }
    }
}

enum SettingsSectionGroup: String, CaseIterable {
    case top
    case speechAndText
    case automation
    case bottom

    var title: String? {
        switch self {
        case .top, .bottom: return nil
        case .speechAndText: return "Speech & Text"
        case .automation: return "Automation"
        }
    }

    var sections: [SettingsSection] {
        SettingsSection.allCases.filter { $0.group == self }
    }
}

struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .general
    @EnvironmentObject var snippetStore: SnippetStore

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedSection) {
                ForEach(SettingsSectionGroup.allCases, id: \.self) { group in
                    if let title = group.title {
                        Section(title) {
                            ForEach(group.sections) { section in
                                sidebarLabel(for: section)
                                    .tag(section)
                            }
                        }
                    } else {
                        ForEach(group.sections) { section in
                            sidebarLabel(for: section)
                                .tag(section)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(width: 220)

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .general:
            GeneralSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .speechRecognition:
            SpeechRecognitionSettingsView()
        case .textProcessing:
            TextProcessingSettingsView()
        case .snippets:
            SnippetSettingsView()
        case .commands:
            VoiceCommandSettingsView()
        case .history:
            HistoryView()
        case .advanced:
            AdvancedSettingsView()
        }
    }

    @ViewBuilder
    private func sidebarLabel(for section: SettingsSection) -> some View {
        if section == .snippets && !snippetStore.snippets.isEmpty {
            HStack {
                Label { Text(section.title) } icon: { section.icon.frame(width: 18, height: 18) }
                Spacer()
                Text("\(snippetStore.snippets.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        } else {
            Label { Text(section.title) } icon: { section.icon.frame(width: 18, height: 18) }
        }
    }
}
