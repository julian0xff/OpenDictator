import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
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
        case .speechRecognition: return "Speech Recognition"
        case .textProcessing: return "Text Processing"
        case .snippets: return "Snippets"
        case .commands: return "Commands"
        case .history: return "History"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .speechRecognition: return "waveform"
        case .textProcessing: return "textformat.abc"
        case .snippets: return "text.badge.plus"
        case .commands: return "command"
        case .history: return "chart.bar.fill"
        case .advanced: return "slider.horizontal.3"
        }
    }

    var group: SettingsSectionGroup {
        switch self {
        case .general: return .top
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
        NavigationSplitView {
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
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            detailView
        }
        .frame(width: 720, height: 480)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .general:
            GeneralSettingsView()
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
                Label(section.title, systemImage: section.icon)
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
            Label(section.title, systemImage: section.icon)
        }
    }
}
