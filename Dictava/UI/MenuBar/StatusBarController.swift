import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?
    private let fluidAudioModelManager: FluidAudioModelManager
    private var currentDictationState: DictationState = .idle

    init(dictationSession: DictationSession, modelManager: ModelManager, fluidAudioModelManager: FluidAudioModelManager, settingsStore: SettingsStore, transcriptionLogStore: TranscriptionLogStore) {
        self.fluidAudioModelManager = fluidAudioModelManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()

        super.init()

        let contentView = StatusBarPopoverView(
            dictationSession: dictationSession,
            modelManager: modelManager,
            fluidAudioModelManager: fluidAudioModelManager,
            settingsStore: settingsStore,
            transcriptionLogStore: transcriptionLogStore
        )
        popover.contentSize = NSSize(width: 320, height: 340)
        popover.behavior = .transient
        let hostingController = NSHostingController(rootView: contentView.frame(width: 320))
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        NotificationCenter.default.addObserver(self, selector: #selector(popoverDidClose), name: NSPopover.didCloseNotification, object: popover)

        updateIcon()

        // Update icon based on dictation state
        dictationSession.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.currentDictationState = state
                self?.updateIcon()
            }
            .store(in: &cancellables)

        // Update icon when download state changes (blue waveform while downloading)
        fluidAudioModelManager.$isDownloading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIcon()
            }
            .store(in: &cancellables)
    }

    @objc private func popoverDidClose() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
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
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let state = currentDictationState

        // Downloading: blue waveform
        if fluidAudioModelManager.isDownloading && state == .idle {
            let icon = NSImage(named: "MenuBarIconBlue")
            icon?.isTemplate = false
            button.image = icon
            return
        }

        // Listening: red waveform
        if state == .listening {
            let icon = NSImage(named: "MenuBarIconRed")
            icon?.isTemplate = false
            button.image = icon
            return
        }

        // Idle: black waveform (template — auto-inverts for dark/light mode)
        if state == .idle {
            let icon = NSImage(named: "MenuBarIconBlack")
            icon?.isTemplate = true
            button.image = icon
            return
        }

        // Transient states: SF Symbols
        let symbolName: String
        switch state {
        case .loadingModel:
            symbolName = "arrow.down.circle"
        case .transcribing, .processing:
            symbolName = "text.bubble.fill"
        case .injecting:
            symbolName = "keyboard.fill"
        case .executingCommand:
            symbolName = "command"
        case .idle, .listening:
            return // handled above
        }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: state.displayText)
        button.image?.isTemplate = true
    }
}

// MARK: - Popover View

struct StatusBarPopoverView: View {
    @ObservedObject var dictationSession: DictationSession
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var fluidAudioModelManager: FluidAudioModelManager
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var transcriptionLogStore: TranscriptionLogStore

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeaderView(
                state: dictationSession.state,
                languageCode: settingsStore.selectedLanguage,
                providerName: dictationSession.activeProviderDisplayName
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            PopoverBodyView(
                dictationSession: dictationSession,
                modelManager: modelManager,
                fluidAudioModelManager: fluidAudioModelManager,
                settingsStore: settingsStore
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if dictationSession.state == .idle {
                QuickStatsView(transcriptionLogStore: transcriptionLogStore)
                    .padding(.horizontal, 16)

                let recent = transcriptionLogStore.recentTranscriptions(limit: 3)
                if !recent.isEmpty {
                    Divider()
                    PopoverRecentView(transcriptions: recent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            }

            Divider()

            PopoverFooterView()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .animation(.easeInOut(duration: 0.2), value: dictationSession.state)
    }
}

// MARK: - Header

private struct PopoverHeaderView: View {
    let state: DictationState
    let languageCode: String
    let providerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("Dictava")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                if state == .idle {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                    Text(state.displayText)
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if state == .listening {
                    PulsingDot()
                    Text(state.displayText)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text(state.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if state == .idle || state == .listening {
                let languageName = SupportedLanguage.all.first(where: { $0.code == languageCode })?.name ?? languageCode
                Text("\(languageName) \u{00B7} \(providerName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 7, height: 7)
            .opacity(isPulsing ? 0.4 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Body

private struct PopoverBodyView: View {
    @ObservedObject var dictationSession: DictationSession
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var fluidAudioModelManager: FluidAudioModelManager
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject private var permissions = PermissionManager.shared

    private var isFluidAudioActive: Bool {
        settingsStore.preferredProvider(for: settingsStore.selectedLanguage) == .fluidAudio
    }

    /// Whether the active provider's model is ready for dictation.
    private var isModelReady: Bool {
        if isFluidAudioActive {
            return fluidAudioModelManager.isDownloaded && !fluidAudioModelManager.isDownloading
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Error banner (hide stale "not downloaded" error during download)
            if let error = dictationSession.error,
               !(isFluidAudioActive && fluidAudioModelManager.isDownloading) {
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

            // Model download progress
            if isFluidAudioActive && fluidAudioModelManager.isDownloading {
                HStack(spacing: 8) {
                    ProgressView(value: fluidAudioModelManager.downloadProgress, total: 1.0)
                    Text("\(Int(fluidAudioModelManager.downloadProgress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
                Text("Downloading Parakeet model...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isFluidAudioActive && !fluidAudioModelManager.isDownloaded {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("Parakeet model required — download in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.quaternary)
                .cornerRadius(6)
            }

            if permissions.allPermissionsGranted {
                if isModelReady {
                    WaveformHeroView(dictationSession: dictationSession)
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

// MARK: - Waveform Hero

private struct WaveformHeroView: View {
    @ObservedObject var dictationSession: DictationSession

    var body: some View {
        Button {
            dictationSession.toggle()
        } label: {
            VStack(spacing: 8) {
                switch dictationSession.state {
                case .idle:
                    AudioWaveformView(
                        levels: Array(repeating: Float(0.05), count: 20),
                        color: .secondary.opacity(0.3)
                    )
                    .frame(height: 32)

                    Text("\u{2325}Space to dictate")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .listening:
                    AudioWaveformView(
                        levels: dictationSession.audioLevelHistory,
                        color: .red
                    )
                    .frame(height: 32)

                    if !dictationSession.liveText.isEmpty {
                        Text(dictationSession.liveText)
                            .font(.system(.caption, design: .rounded))
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                default:
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
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Stats

private struct QuickStatsView: View {
    @ObservedObject var transcriptionLogStore: TranscriptionLogStore

    var body: some View {
        let count = transcriptionLogStore.todayCount()
        if count > 0 {
            let duration = transcriptionLogStore.todayListeningTime()
            Text("Today: \(count) dictation\(count == 1 ? "" : "s") \u{00B7} \(formatCompactDuration(duration))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
        }
    }

    private func formatCompactDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            let mins = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(mins)m \(secs)s"
        } else {
            let hours = Int(seconds / 3600)
            let mins = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(mins)m"
        }
    }
}

// MARK: - Recent Transcriptions

private struct PopoverRecentView: View {
    let transcriptions: [TranscriptionLog]
    @State private var hoveredID: UUID?
    @State private var copiedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: "Recent" left, "View All →" right
            HStack {
                Text("Recent")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    NSApp.sendAction(#selector(AppDelegate.openHistoryWindow), to: nil, from: nil)
                } label: {
                    Text("View All \u{2192}")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            VStack(spacing: 6) {
                ForEach(transcriptions) { log in
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(log.text, forType: .string)
                        copiedID = log.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedID == log.id {
                                copiedID = nil
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.text)
                                .font(.caption)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 0) {
                                Text(relativeTime(log.timestamp))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()

                                Spacer()

                                if copiedID == log.id {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .opacity(hoveredID == log.id ? 1 : 0)
                                }
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered in
                        hoveredID = hovered ? log.id : nil
                    }
                }
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}

// MARK: - Footer

private struct PopoverFooterView: View {
    var body: some View {
        HStack(spacing: 12) {
            footerButton(icon: "gear", label: "Settings", color: .gray) {
                NSApp.sendAction(#selector(AppDelegate.openSettingsWindow), to: nil, from: nil)
            }

            footerButton(icon: "clock.arrow.circlepath", label: "History", color: .indigo) {
                NSApp.sendAction(#selector(AppDelegate.openHistoryWindow), to: nil, from: nil)
            }

            footerButton(icon: "power", label: "Quit", color: .red) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func footerButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(color))

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(FooterButtonStyle())
    }
}

private struct FooterButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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
