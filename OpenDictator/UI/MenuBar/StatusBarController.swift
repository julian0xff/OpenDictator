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

        // Force light appearance to match warm theme
        popover.appearance = NSAppearance(named: .aqua)

        settingsStore.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
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
                popoverWindow.backgroundColor = NSColor(red: 245/255, green: 241/255, blue: 236/255, alpha: 1)
                popoverWindow.isOpaque = false
            }
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopoverAndStopMonitor()
            }
        }
    }

    func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
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

    private var theme: SettingsTheme { .warm }

    var body: some View {
        VStack(spacing: 12) {
            PopoverHeaderView(state: dictationSession.state)

            PopoverBodyView(
                dictationSession: dictationSession,
                modelManager: modelManager,
                fluidAudioModelManager: fluidAudioModelManager,
                settingsStore: settingsStore
            )

            if dictationSession.state == .idle {
                QuickStatsView(transcriptionLogStore: transcriptionLogStore)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                let recent = transcriptionLogStore.recentTranscriptions(limit: 3)
                if !recent.isEmpty {
                    PopoverRecentView(transcriptions: recent)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer(minLength: 0)

            PopoverFooterView()
        }
        .padding(16)
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
                .font(.custom("Inter", size: 11).weight(.medium))
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
    @Environment(\.settingsTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 15))
                .foregroundStyle(theme.controlAccent)

            Text("OpenDictator")
                .font(.custom("Nunito", size: 15).weight(.bold))
                .foregroundStyle(theme.textPrimary)

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
            // Setup required banner
            if !settingsStore.hasOpenedSettings {
                Button {
                    NSApp.sendAction(#selector(AppDelegate.openSettingsWindow), to: nil, from: nil)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gear.badge")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.controlAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Settings to get started")
                                .font(.custom("Inter", size: 12).weight(.semibold))
                                .foregroundStyle(theme.textPrimary)
                            Text("Dictation is disabled until you configure the app.")
                                .font(.custom("Inter", size: 11))
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(theme.textTertiary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.controlAccent.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.controlAccent.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

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

            if permissions.allPermissionsGranted && settingsStore.hasOpenedSettings {
                if isModelReady {
                    WaveformHeroView(dictationSession: dictationSession)
                }
            } else if !permissions.allPermissionsGranted {
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

    // Gentle wave pattern for idle waveform (15 bars matching design)
    private static let idleWaveformLevels: [Float] = [
        0.30, 0.50, 0.70, 0.90, 0.60, 1.00, 0.45, 0.80,
        0.35, 0.65, 0.95, 0.55, 0.40, 0.75, 0.25
    ]

    private var idleHero: some View {
        VStack(spacing: 14) {
            ClassicBarsView(
                levels: Self.idleWaveformLevels,
                color: theme.textTertiary.opacity(0.4),
                maxHeight: 40,
                barSpacing: 3
            )
            .frame(height: 40)

            HStack(spacing: 6) {
                Text("Press")
                    .font(.custom("Inter", size: 12))
                    .foregroundStyle(Color(hex: "A09A93"))

                Text("\u{2325} Space")
                    .font(.custom("JetBrains Mono", size: 11).weight(.medium))
                    .foregroundStyle(Color(hex: "7A756E"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: "F5F1EC"))
                    )

                Text("to dictate")
                    .font(.custom("Inter", size: 12))
                    .foregroundStyle(Color(hex: "A09A93"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "FEFCFA"))
                .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        )
    }

    private var listeningHero: some View {
        VStack(spacing: 12) {
            ClassicBarsView(
                levels: dictationSession.audioLevelHistory,
                color: Color(hex: "C4703E")
            )
            .frame(height: 48)

            if !dictationSession.liveText.isEmpty {
                Text(dictationSession.liveText)
                    .font(.custom("Inter", size: 13))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }

            Text("Tap to stop")
                .font(.custom("Inter", size: 11))
                .foregroundStyle(Color(hex: "A09A93"))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "FEFCFA"))
                .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "C4703E").opacity(0.2), lineWidth: 1)
        )
    }

    private var processingHero: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
            Text(dictationSession.state.displayText)
                .font(.custom("Inter", size: 13))
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
    let topLabel: String
    let value: String
    let bottomLabel: String
    @Environment(\.settingsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(topLabel)
                .font(.custom("Inter", size: 10).weight(.medium))
                .kerning(0.4)
                .foregroundStyle(Color(hex: "A09A93"))

            Text(value)
                .font(.custom("Nunito", size: 20).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(theme.textPrimary)
                .contentTransition(.numericText())

            Text(bottomLabel)
                .font(.custom("Inter", size: 11))
                .foregroundStyle(Color(hex: "7A756E"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "FEFCFA"))
                .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
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
            HStack(spacing: 10) {
                PopoverStatTileView(
                    topLabel: "TODAY",
                    value: "\(count)",
                    bottomLabel: count == 1 ? "dictation" : "dictations"
                )
                PopoverStatTileView(
                    topLabel: "LISTENING",
                    value: formatCompactDuration(duration),
                    bottomLabel: "minutes today"
                )
            }
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
        VStack(alignment: .leading, spacing: 8) {
            // Header: "RECENT" left, "View All" right
            HStack {
                Text("RECENT")
                    .font(.custom("Inter", size: 10).weight(.semibold))
                    .kerning(0.8)
                    .foregroundStyle(Color(hex: "B5AFA8"))

                Spacer()

                Button {
                    NSApp.sendAction(#selector(AppDelegate.openHistoryWindow), to: nil, from: nil)
                } label: {
                    Text("View All")
                        .font(.custom("Inter", size: 11).weight(.medium))
                        .foregroundStyle(Color(hex: "C4703E"))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 8) {
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
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(log.text)
                                    .font(.custom("Inter", size: 12))
                                    .lineLimit(1)
                                    .foregroundStyle(theme.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(relativeTime(log.timestamp))
                                    .font(.custom("Inter", size: 10))
                                    .foregroundStyle(Color(hex: "B5AFA8"))
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: "FEFCFA"))
                                .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
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
        HStack(spacing: 8) {
            footerButton(icon: "gear", label: "Settings") {
                NSApp.sendAction(#selector(AppDelegate.openSettingsWindow), to: nil, from: nil)
            }

            footerButton(icon: "clock.arrow.circlepath", label: "History") {
                NSApp.sendAction(#selector(AppDelegate.openHistoryWindow), to: nil, from: nil)
            }

            footerButton(icon: "power", label: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func footerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "7A756E"))

                Text(label)
                    .font(.custom("Inter", size: 12).weight(.medium))
                    .foregroundStyle(Color(hex: "7A756E"))
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
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "FEFCFA"))
                    .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .opacity(isHovered ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
