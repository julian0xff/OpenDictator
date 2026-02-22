import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    init(dictationSession: DictationSession, modelManager: ModelManager, settingsStore: SettingsStore, transcriptionLogStore: TranscriptionLogStore) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        super.init()

        let contentView = StatusBarPopoverView(
            dictationSession: dictationSession,
            modelManager: modelManager,
            settingsStore: settingsStore,
            transcriptionLogStore: transcriptionLogStore
        )
        popover.contentSize = NSSize(width: 300, height: 340)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        updateIcon(for: .idle)

        // Update icon based on dictation state
        dictationSession.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateIcon(for: state)
            }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopoverAndStopMonitor()
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopoverAndStopMonitor()
            }
        }
    }

    private func closePopoverAndStopMonitor() {
        popover.performClose(nil)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }

    private func updateIcon(for state: DictationState) {
        guard let button = statusItem.button else { return }

        if state == .idle {
            let icon = NSImage(named: "MenuBarIcon")
                ?? NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Dictava")
            icon?.isTemplate = true
            button.image = icon
            return
        }

        let symbolName: String
        switch state {
        case .listening:
            symbolName = "mic.badge.plus"
        case .transcribing, .processing:
            symbolName = "text.bubble.fill"
        case .injecting:
            symbolName = "keyboard.fill"
        case .executingCommand:
            symbolName = "command"
        case .idle:
            return // handled above
        }

        if state == .listening {
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: state.displayText)?
                .withSymbolConfiguration(config)
            button.image?.isTemplate = false
        } else {
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: state.displayText)
            button.image?.isTemplate = true
        }
    }
}

struct StatusBarPopoverView: View {
    @ObservedObject var dictationSession: DictationSession
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var transcriptionLogStore: TranscriptionLogStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Dictava")
                    .font(.headline)
                Spacer()
                Text(dictationSession.state.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if dictationSession.state == .listening {
                AudioLevelBar(level: dictationSession.audioLevel)
                    .frame(height: 4)
            }

            if !dictationSession.liveText.isEmpty {
                Text(dictationSession.liveText)
                    .font(.system(.body, design: .rounded))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary)
                    .cornerRadius(6)
            }

            if let error = dictationSession.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(dictationSession.state.isActive ? "Stop" : "Start Dictation") {
                    dictationSession.toggle()
                }
                .keyboardShortcut(.defaultAction)

                Spacer()

                if #available(macOS 14.0, *) {
                    SettingsLink {
                        Image(systemName: "gear")
                    }
                    .buttonStyle(.borderless)
                } else {
                    Button {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } label: {
                        Image(systemName: "gear")
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack {
                Text("Model: \(modelManager.availableModels.first(where: { $0.name == settingsStore.selectedModelName })?.displayName ?? settingsStore.selectedModelName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("⌥Space")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if transcriptionLogStore.todayCount() > 0 {
                let todayTime = transcriptionLogStore.todayListeningTime()
                Text("\(transcriptionLogStore.todayCount()) dictation\(transcriptionLogStore.todayCount() == 1 ? "" : "s") today · \(formatListeningTime(todayTime)) listening")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            if dictationSession.state == .idle {
                let recent = transcriptionLogStore.recentTranscriptions(limit: 3)
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RECENT")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        ForEach(recent) { log in
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(log.text, forType: .string)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(relativeTime(log.timestamp))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 40, alignment: .leading)
                                    Text(log.text)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()
                }
            }

            HStack {
                Button {
                    openWindow(id: "history")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("History", systemImage: "chart.bar.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Quit Dictava") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .animation(.easeInOut(duration: 0.2), value: dictationSession.state)
    }

    private func formatListeningTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else {
            return "\(Int(seconds / 60))m"
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}

struct AudioLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 2)
                .fill(.green.gradient)
                .frame(width: geometry.size.width * CGFloat(level))
        }
        .background(.quaternary)
        .cornerRadius(2)
    }
}
