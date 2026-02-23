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
        let hostingController = NSHostingController(rootView: contentView.frame(width: 300))
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController

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
        case .loadingModel:
            symbolName = "arrow.down.circle"
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

// MARK: - Popover View

struct StatusBarPopoverView: View {
    @ObservedObject var dictationSession: DictationSession
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var transcriptionLogStore: TranscriptionLogStore

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeaderView(state: dictationSession.state)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Divider()

            PopoverBodyView(
                dictationSession: dictationSession,
                modelManager: modelManager,
                settingsStore: settingsStore
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if dictationSession.state == .idle {
                let recent = transcriptionLogStore.recentTranscriptions(limit: 3)
                if !recent.isEmpty {
                    Divider()
                    PopoverRecentView(transcriptions: recent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }

            Divider()

            PopoverFooterView()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .animation(.easeInOut(duration: 0.2), value: dictationSession.state)
    }
}

// MARK: - Header

private struct PopoverHeaderView: View {
    let state: DictationState

    var body: some View {
        HStack(spacing: 8) {
            Text("Dictava")
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            if state == .listening {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
            }

            Text(state.displayText)
                .font(.caption)
                .foregroundStyle(state == .listening ? .red : .secondary)
        }
    }
}

// MARK: - Body

private struct PopoverBodyView: View {
    @ObservedObject var dictationSession: DictationSession
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject private var permissions = PermissionManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Error banner
            if let error = dictationSession.error {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(8)
                .background(.orange.opacity(0.12))
                .cornerRadius(6)
            }

            // Listening: audio bar + live text
            if dictationSession.state == .listening {
                AudioLevelBar(level: dictationSession.audioLevel)
                    .frame(height: 4)

                if !dictationSession.liveText.isEmpty {
                    Text(dictationSession.liveText)
                        .font(.system(.body, design: .rounded))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary)
                        .cornerRadius(6)
                }
            }

            // Processing states: spinner
            if dictationSession.state != .idle && dictationSession.state != .listening {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                    Text(dictationSession.state.displayText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if permissions.allPermissionsGranted {
                // Primary action button + hotkey
                HStack(spacing: 0) {
                    Button(dictationSession.state.isActive ? "Stop" : "Start Dictation") {
                        dictationSession.toggle()
                    }
                    .keyboardShortcut(.defaultAction)
                    .tint(dictationSession.state == .listening ? .red : nil)

                    Spacer()

                    Text("⌥Space")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Model info (idle only)
                if dictationSession.state == .idle {
                    let displayName = modelManager.availableModels
                        .first(where: { $0.name == settingsStore.selectedModelName })?
                        .displayName ?? settingsStore.selectedModelName
                    Text(displayName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                // Permission buttons
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if permissions.microphoneStatus != .granted {
                            Button {
                                Task { await PermissionManager.shared.requestMicrophone() }
                            } label: {
                                Label("Microphone", systemImage: "mic.fill")
                            }
                            .controlSize(.small)
                        }

                        if permissions.accessibilityStatus != .granted {
                            Button {
                                PermissionManager.shared.requestAccessibility()
                            } label: {
                                Label("Accessibility", systemImage: "accessibility")
                            }
                            .controlSize(.small)
                        }
                    }

                    Text("Permissions required for dictation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Recent Transcriptions

private struct PopoverRecentView: View {
    let transcriptions: [TranscriptionLog]
    @State private var hoveredID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENT")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 6)

            ForEach(transcriptions) { log in
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.text, forType: .string)
                } label: {
                    HStack(spacing: 8) {
                        Text(relativeTime(log.timestamp))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .leading)
                            .monospacedDigit()

                        Text(log.text)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .opacity(hoveredID == log.id ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .onHover { hovered in
                    hoveredID = hovered ? log.id : nil
                }
            }
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

// MARK: - Footer

private struct PopoverFooterView: View {
    var body: some View {
        HStack(spacing: 8) {
            Button {
                NSApp.sendAction(#selector(AppDelegate.openSettingsWindow), to: nil, from: nil)
            } label: {
                Label("Settings...", systemImage: "gear")
                    .font(.callout)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FooterButtonStyle())

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.callout)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FooterButtonStyle())
        }
    }
}

private struct FooterButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered ? .primary : .secondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Audio Level Bar

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
