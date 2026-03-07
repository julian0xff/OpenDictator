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
        popover.appearance = NSAppearance(named: .darkAqua)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        statusItem.isVisible = settingsStore.showMenuBarIcon

        NotificationCenter.default.addObserver(self, selector: #selector(popoverDidClose), name: NSPopover.didCloseNotification, object: popover)

        updateIcon()

        dictationSession.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.currentDictationState = state
                self?.updateIcon()
            }
            .store(in: &cancellables)

        fluidAudioModelManager.$isDownloading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIcon()
            }
            .store(in: &cancellables)

        settingsStore.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
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
                popoverWindow.backgroundColor = NSColor(red: 12/255, green: 12/255, blue: 12/255, alpha: 1)
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

        if fluidAudioModelManager.isDownloading && state == .idle {
            let icon = NSImage(named: "MenuBarIconBlue")
            icon?.isTemplate = false
            button.image = icon
            return
        }

        if state == .listening {
            let icon = NSImage(named: "MenuBarIconRed")
            icon?.isTemplate = false
            button.image = icon
            return
        }

        if state == .idle {
            let icon = NSImage(named: "MenuBarIconBlack")
            icon?.isTemplate = true
            button.image = icon
            return
        }

        let symbolName: String
        switch state {
        case .loadingModel: symbolName = "arrow.down.circle"
        case .transcribing, .processing: symbolName = "text.bubble.fill"
        case .injecting: symbolName = "keyboard.fill"
        case .idle, .listening: return
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

    private var theme: DictavaTheme { .ember }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            PopoverHeaderView(
                state: dictationSession.state,
                languageCode: settingsStore.selectedLanguage,
                providerName: dictationSession.activeProviderDisplayName
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle().fill(theme.border).frame(height: 1)

            // Body
            PopoverBodyView(
                dictationSession: dictationSession,
                fluidAudioModelManager: fluidAudioModelManager,
                settingsStore: settingsStore
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Language + Model selectors (only when idle)
            if dictationSession.state == .idle {
                PopoverSelectorRow(dictationSession: dictationSession, settingsStore: settingsStore, fluidAudioModelManager: fluidAudioModelManager)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity)

                let recent = transcriptionLogStore.recentTranscriptions(limit: 3)
                if !recent.isEmpty {
                    Rectangle().fill(theme.border).frame(height: 1)
                    PopoverRecentView(transcriptions: recent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .transition(.opacity)
                }
            }

            Rectangle().fill(theme.border).frame(height: 1)

            PopoverFooterView()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .background(theme.bg)
        .environment(\.theme, .ember)
        .animation(.smooth(duration: 0.25), value: dictationSession.state)
    }
}

// MARK: - Status Pill

private struct StatusPillView: View {
    let state: DictationState
    @Environment(\.theme) private var theme

    private var color: Color {
        switch state {
        case .idle: theme.success
        case .listening: theme.accent
        default: theme.textSecondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if state == .listening {
                PulsingDot(color: theme.accent)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }

            Text(state.displayText)
                .font(.system(size: 11, weight: .medium))
                .contentTransition(.interpolate)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
        .foregroundStyle(color)
    }
}

private struct PulsingDot: View {
    var color: Color
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

// MARK: - Header

private struct PopoverHeaderView: View {
    let state: DictationState
    let languageCode: String
    let providerName: String
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 15))
                .foregroundStyle(theme.textPrimary)

            VStack(alignment: .leading, spacing: 1) {
                Text("Dictava")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                let languageName = SupportedLanguage.all.first(where: { $0.code == languageCode })?.name ?? languageCode
                Text("\(languageName) \u{00B7} \(providerName)")
                    .font(.caption2)
                    .foregroundStyle(theme.textMuted)
                    .opacity(state == .idle || state == .listening ? 1 : 0)
            }

            Spacer()

            StatusPillView(state: state)
        }
    }
}

// MARK: - Body

private struct PopoverBodyView: View {
    @ObservedObject var dictationSession: DictationSession
    @ObservedObject var fluidAudioModelManager: FluidAudioModelManager
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject private var permissions = PermissionManager.shared
    @Environment(\.theme) private var theme

    private var isFluidAudioActive: Bool {
        settingsStore.preferredProvider(for: settingsStore.selectedLanguage) == .fluidAudio
    }

    private var isModelReady: Bool {
        if isFluidAudioActive {
            return fluidAudioModelManager.isDownloaded && !fluidAudioModelManager.isDownloading
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Error banner
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
                .background(theme.warningDim)
                .cornerRadius(DictavaTheme.radiusSm)
            }

            // Model download progress (inline in hero area)
            if isFluidAudioActive && fluidAudioModelManager.isDownloading {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView(value: fluidAudioModelManager.downloadProgress, total: 1.0)
                            .tint(theme.accent)
                        Text("\(Int(fluidAudioModelManager.downloadProgress * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                    Text("Downloading Parakeet model...")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: DictavaTheme.radiusLg)
                        .fill(theme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: DictavaTheme.radiusLg)
                                .stroke(theme.border, lineWidth: 1)
                        )
                )
            } else if isFluidAudioActive && !fluidAudioModelManager.isDownloaded {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(theme.textSecondary)
                        .font(.caption)
                    Text("Parakeet model required \u{2014} download in Settings.")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(8)
                .background(theme.surface)
                .cornerRadius(DictavaTheme.radiusSm)
            }

            if permissions.allPermissionsGranted {
                if isModelReady {
                    WaveformHeroView(dictationSession: dictationSession)
                }
            } else {
                // Permission buttons
                VStack(spacing: 6) {
                    if permissions.microphoneStatus != .granted {
                        permissionButton(
                            icon: "mic.fill",
                            label: "Grant Microphone Access"
                        ) {
                            Task { await PermissionManager.shared.requestMicrophone() }
                        }
                    }

                    if permissions.accessibilityStatus != .granted {
                        permissionButton(
                            icon: "accessibility",
                            label: "Grant Accessibility Access"
                        ) {
                            PermissionManager.shared.requestAccessibility()
                        }
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

    private func permissionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.warning)
                    .frame(width: 20, height: 20)
                    .background(theme.warningDim)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(theme.textMuted)
            }
            .padding(8)
            .background(theme.surface)
            .cornerRadius(DictavaTheme.radiusSm)
            .overlay(
                RoundedRectangle(cornerRadius: DictavaTheme.radiusSm)
                    .stroke(theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Waveform Hero

private struct WaveformHeroView: View {
    @ObservedObject var dictationSession: DictationSession
    @Environment(\.theme) private var theme
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
        case .idle: idleHero
        case .listening: listeningHero
        default: processingHero
        }
    }

    private var idleHero: some View {
        VStack(spacing: 8) {
            ClassicBarsView(
                levels: Array(repeating: Float(0.08), count: 20),
                color: theme.textMuted.opacity(0.4)
            )
            .frame(height: 36)

            HStack {
                Text("\u{2325}Space to dictate")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                Spacer()
                Image(systemName: "mic.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 76)
        .background(
            RoundedRectangle(cornerRadius: DictavaTheme.radiusLg)
                .fill(theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DictavaTheme.radiusLg)
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
                color: theme.accent
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
                    .foregroundStyle(theme.accent.opacity(0.7))
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DictavaTheme.radiusLg)
                .fill(theme.accent.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: DictavaTheme.radiusLg)
                        .strokeBorder(theme.accent.opacity(0.2), lineWidth: 1)
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
            RoundedRectangle(cornerRadius: DictavaTheme.radiusLg)
                .fill(theme.surface)
        )
    }
}

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

// MARK: - Language + Model Selectors

private struct PopoverSelectorRow: View {
    @ObservedObject var dictationSession: DictationSession
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var fluidAudioModelManager: FluidAudioModelManager
    @Environment(\.theme) private var theme

    private var currentLanguage: SupportedLanguage {
        SupportedLanguage.all.first(where: { $0.code == settingsStore.selectedLanguage }) ?? SupportedLanguage.all[0]
    }

    private var currentProvider: String {
        settingsStore.preferredProvider(for: settingsStore.selectedLanguage) == .fluidAudio ? "Parakeet" : "WhisperKit"
    }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(SupportedLanguage.all) { lang in
                    Button {
                        dictationSession.switchLanguage(to: lang.code)
                    } label: {
                        HStack {
                            Text("\(lang.flag) \(lang.name)")
                            if lang.code == settingsStore.selectedLanguage {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(currentLanguage.flag) \(currentLanguage.name)")
                        .font(.caption)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(theme.textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: DictavaTheme.radiusSm)
                        .fill(theme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: DictavaTheme.radiusSm)
                                .stroke(theme.border, lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)

            Menu {
                Button {
                    settingsStore.setPreferredProvider(.fluidAudio, for: settingsStore.selectedLanguage)
                    dictationSession.switchProvider(to: .fluidAudio)
                } label: {
                    HStack {
                        Text("Parakeet")
                        if settingsStore.preferredProvider(for: settingsStore.selectedLanguage) == .fluidAudio {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Button {
                    settingsStore.setPreferredProvider(.whisperKit, for: settingsStore.selectedLanguage)
                    dictationSession.switchProvider(to: .whisperKit)
                } label: {
                    HStack {
                        Text("WhisperKit")
                        if settingsStore.preferredProvider(for: settingsStore.selectedLanguage) == .whisperKit {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentProvider)
                        .font(.caption)
                        .foregroundStyle(theme.textPrimary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(theme.textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: DictavaTheme.radiusSm)
                        .fill(theme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: DictavaTheme.radiusSm)
                                .stroke(theme.border, lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
        }
    }
}

// MARK: - Recent Transcriptions

private struct PopoverRecentView: View {
    let transcriptions: [TranscriptionLog]
    @Environment(\.theme) private var theme
    @State private var hoveredID: UUID?
    @State private var copiedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("RECENT")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(theme.textMuted)
                Spacer()
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
                                if copiedID == log.id { copiedID = nil }
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
                                    .foregroundStyle(theme.textMuted)
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
                                    .foregroundStyle(theme.textMuted)
                                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: DictavaTheme.radiusSm)
                                .fill(theme.surface.opacity(hoveredID == log.id ? 1.0 : 0.5))
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
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            Button {
                NSApp.sendAction(#selector(AppDelegate.openSettingsWindow), to: nil, from: nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gear")
                        .font(.system(size: 11))
                    Text("Settings")
                        .font(.system(size: 12))
                }
                .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textMuted)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }
}
