import AppKit
import SwiftUI
import Combine

@MainActor
final class DictationIndicatorWindow {
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private let settingsStore: SettingsStore
    private let customThemeStore: CustomThemeStore
    private var isHiding = false

    init(dictationSession: DictationSession, settingsStore: SettingsStore, customThemeStore: CustomThemeStore) {
        self.settingsStore = settingsStore
        self.customThemeStore = customThemeStore

        dictationSession.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state.isActive && self.settingsStore.showFloatingIndicator {
                    self.show(session: dictationSession)
                } else {
                    self.hide()
                }
            }
            .store(in: &cancellables)
    }

    private func show(session: DictationSession) {
        isHiding = false
        // Cancel any in-progress hide animation immediately
        panel?.animator().alphaValue = 0

        if panel == nil {
            let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let contentView = DictationIndicatorView(session: session, settingsStore: settingsStore, customThemeStore: customThemeStore, isDarkMode: isDarkMode)
            let hostingView = NSHostingView(rootView: contentView)
            hostingView.sizingOptions = [.intrinsicContentSize]

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
            panel.contentView = hostingView
            panel.isMovableByWindowBackground = true
            panel.hasShadow = false
            panel.appearance = nil

            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - 160
                let y = screenFrame.maxY - 70
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }

            self.panel = panel
        }

        panel?.alphaValue = 0
        panel?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.panel?.animator().alphaValue = 1
        }

        // Resize panel after SwiftUI completes its layout pass for the new state
        DispatchQueue.main.async { [weak self] in
            self?.resizePanelToFit()
        }
    }

    private func resizePanelToFit() {
        guard let panel, let hostingView = panel.contentView as? NSHostingView<DictationIndicatorView> else { return }
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        var frame = panel.frame
        let midX = frame.midX
        let maxY = frame.maxY
        frame.size = size
        frame.origin.x = midX - size.width / 2
        frame.origin.y = maxY - size.height
        panel.setFrame(frame, display: true)
    }

    private func hide() {
        guard let panel else { return }
        isHiding = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard self?.isHiding == true else { return }
            panel.orderOut(nil)
            self?.isHiding = false
        })
    }
}

// MARK: - Indicator View

struct DictationIndicatorView: View {
    @ObservedObject var session: DictationSession
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var customThemeStore: CustomThemeStore
    var isDarkMode: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var effectiveIsDarkMode: Bool {
        colorScheme == .dark || isDarkMode
    }

    private var theme: IndicatorTheme {
        settingsStore.currentIndicatorTheme(isDarkMode: effectiveIsDarkMode, customThemes: customThemeStore.themes)
    }

    var body: some View {
        HStack(spacing: 10) {
            stateIcon
            centerContent
            if session.state == .listening {
                AudioWaveformView(levels: session.audioLevelHistory, color: theme.waveformColor)
                    .frame(width: 80, height: 24)
            }
        }
        .padding(.horizontal, theme.horizontalPadding)
        .padding(.vertical, theme.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .fill(theme.backgroundColor.opacity(theme.backgroundOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .stroke(theme.borderColor.opacity(theme.borderOpacity), lineWidth: theme.borderWidth)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .fixedSize()
        .animation(.easeInOut(duration: 0.2), value: session.state)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch session.state {
        case .listening:
            EmptyView()
        case .loadingModel, .transcribing, .processing:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
                .tint(theme.textColor)
        case .injecting:
            Image(systemName: "keyboard.fill")
                .font(.system(size: 12))
                .foregroundStyle(theme.textColor)
        case .executingCommand:
            Image(systemName: "command")
                .font(.system(size: 12))
                .foregroundStyle(theme.textColor)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        switch session.state {
        case .listening:
            EmptyView()
        case .loadingModel:
            Text("Loading model...")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(theme.textColor)
        case .transcribing:
            Text("Transcribing...")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(theme.textColor)
        case .processing:
            Text("Processing...")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(theme.textColor)
        case .injecting:
            Text("Typing...")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(theme.textColor)
        case .executingCommand:
            Text("Executing...")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(theme.textColor)
        case .idle:
            EmptyView()
        }
    }
}

// MARK: - Audio Waveform View

struct AudioWaveformView: View {
    let levels: [Float]
    var color: Color = .blue

    private let barCount = 20
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = index < levels.count ? CGFloat(levels[index]) : 0
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: barWidth, height: max(2, level * 28))
                    .animation(.interpolatingSpring(stiffness: 300, damping: 15), value: level)
            }
        }
    }
}
