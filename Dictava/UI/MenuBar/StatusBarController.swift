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
    private let settingsStore: SettingsStore
    private var currentDictationState: DictationState = .idle

    init(dictationSession: DictationSession, modelManager: ModelManager, fluidAudioModelManager: FluidAudioModelManager, settingsStore: SettingsStore, transcriptionLogStore: TranscriptionLogStore) {
        self.fluidAudioModelManager = fluidAudioModelManager
        self.settingsStore = settingsStore
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
        popover.behavior = .transient
        let hostingController = NSHostingController(rootView: contentView.frame(width: 340).frame(minHeight: 280))
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        statusItem.isVisible = settingsStore.showMenuBarIcon

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

        // Sync popover appearance with settings
        popover.appearance = settingsStore.settingsAppearance.nsAppearance

        settingsStore.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.popover.appearance = settingsStore.settingsAppearance.nsAppearance
                if let popoverWindow = self.popover.contentViewController?.view.window {
                    popoverWindow.backgroundColor = settingsStore.settingsAppearance.windowBackgroundColor
                }
                // Sync menu bar icon visibility (debounced to clear activation policy transitions)
                let shouldBeVisible = self.settingsStore.showMenuBarIcon
                guard self.statusItem.isVisible != shouldBeVisible else { return }
                if !shouldBeVisible && self.popover.isShown {
                    self.popover.close()
                }
                self.statusItem.isVisible = shouldBeVisible
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
            PermissionManager.shared.refreshStatuses()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let popoverWindow = popover.contentViewController?.view.window {
                popoverWindow.backgroundColor = settingsStore.settingsAppearance.windowBackgroundColor
                popoverWindow.isOpaque = false
            }
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
    @Environment(\.colorScheme) private var colorScheme

    private var theme: SettingsTheme {
        .resolve(colorScheme: colorScheme, appearance: settingsStore.settingsAppearance)
    }

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeaderView(
                state: dictationSession.state,
                languageCode: settingsStore.selectedLanguage,
                providerName: dictationSession.activeProviderDisplayName
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

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
                    .transition(.opacity.combined(with: .move(edge: .top)))

                let recent = transcriptionLogStore.recentTranscriptions(limit: 3)
                if !recent.isEmpty {
                    Divider()
                    PopoverRecentView(transcriptions: recent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Divider()

            PopoverFooterView()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .background(theme.windowBackground)
        .environment(\.settingsTheme, theme)
        .animation(.smooth(duration: 0.25), value: dictationSession.state)
    }
}

// MARK: - Status Pill

private struct StatusPillView: View {
    let state: DictationState
    @Environment(\.settingsTheme) private var theme

    private var dotColor: Color {
        switch state {
        case .idle: theme.success
        case .listening: .red
        default: theme.textSecondary
        }
    }

    private var tintColor: Color {
        switch state {
        case .idle: theme.success
        case .listening: .red
        default: theme.textSecondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if state == .listening {
                PulsingDot(color: .red)
            } else {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
            }

            Text(state.displayText)
                .font(.system(size: 11, weight: .medium))
                .contentTransition(.interpolate)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(tintColor.opacity(0.12))
        )
        .foregroundStyle(tintColor)
    }
}

// MARK: - Header

private struct PopoverHeaderView: View {
    let state: DictationState
    let languageCode: String
    let providerName: String
    @Environment(\.settingsTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 15))
                .foregroundStyle(theme.textPrimary)

            VStack(alignment: .leading, spacing: 1) {
                Text("Dictava")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                let showSubtitle = state == .idle || state == .listening
                let languageName = SupportedLanguage.all.first(where: { $0.code == languageCode })?.name ?? languageCode
                Text("\(languageName) \u{00B7} \(providerName)")
                    .font(.caption2)
                    .foregroundStyle(theme.textTertiary)
                    .opacity(showSubtitle ? 1 : 0)
            }

            Spacer()

            StatusPillView(state: state)
        }
    }
}

private struct PulsingDot: View {
    var color: Color = .red
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(isPulsing ? 0.4 : 1.0)
            .task {
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
    @Environment(\.settingsTheme) private var theme

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
                        .foregroundStyle(theme.warning)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(8)
                .background(theme.warningBackground)
                .cornerRadius(6)
            }

            // Model download progress
            if isFluidAudioActive && fluidAudioModelManager.isDownloading {
                HStack(spacing: 8) {
                    ProgressView(value: fluidAudioModelManager.downloadProgress, total: 1.0)
                    Text("\(Int(fluidAudioModelManager.downloadProgress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 32, alignment: .trailing)
                }
                Text("Downloading Parakeet model...")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            } else if isFluidAudioActive && !fluidAudioModelManager.isDownloaded {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(theme.textSecondary)
                        .font(.caption)
                    Text("Parakeet model required — download in Settings.")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(8)
                .background(theme.controlBackground)
                .cornerRadius(6)
            }

            if permissions.allPermissionsGranted {
                if isModelReady {
                    WaveformHeroView(dictationSession: dictationSession)
                }
            } else {
                // Permission buttons
                VStack(spacing: 6) {
                    if permissions.microphoneStatus != .granted {
                        Button {
                            Task { await PermissionManager.shared.requestMicrophone() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.warning)
                                    .frame(width: 20, height: 20)
                                    .background(theme.warningBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                Text("Grant Microphone Access")
                                    .font(.caption)
                                    .foregroundStyle(theme.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(theme.textTertiary)
                            }
                            .padding(8)
                            .background(theme.controlBackground)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if permissions.accessibilityStatus != .granted {
                        Button {
                            PermissionManager.shared.requestAccessibility()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "accessibility")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.warning)
                                    .frame(width: 20, height: 20)
                                    .background(theme.warningBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                Text("Grant Accessibility Access")
                                    .font(.caption)
                                    .foregroundStyle(theme.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(theme.textTertiary)
                            }
                            .padding(8)
                            .background(theme.controlBackground)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Required for dictation")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                .animation(.smooth(duration: 0.25), value: permissions.microphoneStatus)
                .animation(.smooth(duration: 0.25), value: permissions.accessibilityStatus)
            }
        }
        .animation(.smooth(duration: 0.25), value: permissions.allPermissionsGranted)
    }
}

// MARK: - Hero Button Style

private struct HeroButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            .opacity(isHovered ? 1.0 : 0.92)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Waveform Hero

private struct WaveformHeroView: View {
    @ObservedObject var dictationSession: DictationSession
    @Environment(\.settingsTheme) private var theme
    @State private var isHeroHovered = false

    var body: some View {
        Button {
            dictationSession.toggle()
        } label: {
            heroContent
                .frame(maxWidth: .infinity)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHeroHovered = hovering
                    }
                }
        }
        .buttonStyle(HeroButtonStyle())
    }

    @ViewBuilder
    private var heroContent: some View {
        switch dictationSession.state {
        case .idle:
            idleHero
        case .listening:
            listeningHero
        default:
            processingHero
        }
    }

    private var idleHero: some View {
        VStack(spacing: 8) {
            ClassicBarsView(
                levels: Array(repeating: Float(0.08), count: 20),
                color: theme.textTertiary.opacity(0.4)
            )
            .frame(height: 36)

            HStack {
                Text("\u{2325}Space to dictate")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)

                Spacer()

                Image(systemName: "mic.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 76)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.cardBackground.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            theme.border.opacity(isHeroHovered ? 1 : 0.6),
                            lineWidth: 1
                        )
                )
        )
    }

    private var listeningHero: some View {
        VStack(spacing: 8) {
            ClassicBarsView(
                levels: dictationSession.audioLevelHistory,
                color: .red
            )
            .frame(height: 36)

            if !dictationSession.liveText.isEmpty {
                Text(dictationSession.liveText)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            HStack {
                Text("Tap to stop")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.7))
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                )
        )
        .frame(minHeight: 76)
    }

    private var processingHero: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
            Text(dictationSession.state.displayText)
                .font(.callout)
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.controlBackground)
        )
    }
}

// MARK: - Stat Tile

private struct PopoverStatTileView: View {
    let value: String
    let label: String
    @Environment(\.settingsTheme) private var theme

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.textPrimary)
                .contentTransition(.numericText())

            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.controlBackground.opacity(0.5))
        )
    }
}

// MARK: - Quick Stats

private struct QuickStatsView: View {
    @ObservedObject var transcriptionLogStore: TranscriptionLogStore

    var body: some View {
        let count = transcriptionLogStore.todayCount()
        if count > 0 {
            let duration = transcriptionLogStore.todayListeningTime()
            HStack(spacing: 8) {
                PopoverStatTileView(
                    value: "\(count)",
                    label: count == 1 ? "dictation" : "dictations"
                )
                PopoverStatTileView(
                    value: formatCompactDuration(duration),
                    label: "listening"
                )
            }
            .padding(.bottom, 6)
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
    @Environment(\.settingsTheme) private var theme
    @State private var hoveredID: UUID?
    @State private var copiedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: "RECENT" left, "View All →" right
            HStack {
                Text("RECENT")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(theme.textTertiary)

                Spacer()

                Button {
                    NSApp.sendAction(#selector(AppDelegate.openHistoryWindow), to: nil, from: nil)
                } label: {
                    Text("View All \u{2192}")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.controlAccent)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            VStack(spacing: 6) {
                ForEach(transcriptions) { log in
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(log.text, forType: .string)
                        withAnimation(.smooth(duration: 0.2)) {
                            copiedID = log.id
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.smooth(duration: 0.2)) {
                                if copiedID == log.id {
                                    copiedID = nil
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(log.text)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundStyle(theme.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(relativeTime(log.timestamp))
                                    .font(.caption2)
                                    .foregroundStyle(theme.textTertiary)
                                    .monospacedDigit()
                            }

                            if copiedID == log.id {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundStyle(theme.success)
                                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
                            } else {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                                    .foregroundStyle(theme.textTertiary)
                                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(theme.controlBackground.opacity(hoveredID == log.id ? 1.0 : 0.5))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered in
                        withAnimation(.easeOut(duration: 0.12)) {
                            hoveredID = hovered ? log.id : nil
                        }
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
    @Environment(\.settingsTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            footerButton(
                icon: "gear",
                label: "Settings",
                iconColor: theme.textSecondary,
                bgColor: theme.controlBackground
            ) {
                NSApp.sendAction(#selector(AppDelegate.openSettingsWindow), to: nil, from: nil)
            }

            footerButton(
                icon: "clock.arrow.circlepath",
                label: "History",
                iconColor: .indigo,
                bgColor: Color.indigo.opacity(0.14)
            ) {
                NSApp.sendAction(#selector(AppDelegate.openHistoryWindow), to: nil, from: nil)
            }

            footerButton(
                icon: "power",
                label: "Quit",
                iconColor: theme.destructive.opacity(0.8),
                bgColor: theme.destructiveBackground
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func footerButton(icon: String, label: String, iconColor: Color, bgColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(bgColor))

                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(FooterButtonStyle())
    }
}

private struct FooterButtonStyle: ButtonStyle {
    @Environment(\.settingsTheme) private var theme
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isHovered ? theme.controlBackground : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
