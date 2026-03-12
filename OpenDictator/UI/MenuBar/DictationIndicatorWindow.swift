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
    private var moveObserver: NSObjectProtocol?
    private var screenConfigObserver: NSObjectProtocol?
    private var activeSpaceObserver: NSObjectProtocol?

    init(dictationSession: DictationSession, settingsStore: SettingsStore, customThemeStore: CustomThemeStore) {
        self.settingsStore = settingsStore
        self.customThemeStore = customThemeStore

        dictationSession.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state.isActive && self.settingsStore.showFloatingIndicator && self.settingsStore.indicatorMode == .floating {
                    self.show(session: dictationSession)
                } else {
                    self.hide()
                }
            }
            .store(in: &cancellables)

        // Resize panel on state changes (content cross-fades need layout pass)
        dictationSession.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.panel != nil, !self.isHiding else { return }
                DispatchQueue.main.async {
                    self.resizePanelToFit()
                }
            }
            .store(in: &cancellables)

        // Resize panel when visualization settings change
        settingsStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, self.panel != nil, !self.isHiding else { return }
                DispatchQueue.main.async {
                    self.resizePanelToFit()
                }
            }
            .store(in: &cancellables)

        screenConfigObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.repositionIfVisible()
        }

        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.repositionIfVisible()
        }
    }

    deinit {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
        if let screenConfigObserver {
            NotificationCenter.default.removeObserver(screenConfigObserver)
        }
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
        }
    }

    private func show(session: DictationSession) {
        isHiding = false

        // If already visible, just ensure it's in front
        if let panel, panel.alphaValue >= 1 {
            panel.orderFront(nil)
            return
        }

        let isFirstShow = (panel == nil)

        if isFirstShow {
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

            // Force layout before first show so size is correct
            hostingView.layoutSubtreeIfNeeded()

            self.panel = panel

            // Observe drag moves to persist position per-screen
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                self?.saveCurrentPosition()
            }
        }

        // Reposition on focused screen every time we transition from hidden → visible
        positionOnFocusedScreen()

        // Opacity-only fade-in — no frame scaling (SwiftUI content handles sizing)
        let animateIn = { [weak self] in
            guard let self, let panel = self.panel else { return }
            self.resizePanelToFit()
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }

        if isFirstShow {
            DispatchQueue.main.async(execute: animateIn)
        } else {
            animateIn()
        }
    }

    private func positionOnFocusedScreen() {
        guard let panel else { return }
        let screen = NSScreen.focused
        let screenFrame = screen.visibleFrame

        // Try saved position for this screen
        if let displayID = screen.displayID,
           let saved = settingsStore.savedIndicatorPosition(forDisplayID: displayID) {
            let topCenterX = screenFrame.origin.x + saved.topCenterXRelative
            let topY = screenFrame.maxY - saved.topOffsetFromVisibleTop
            let origin = NSPoint(x: topCenterX - panel.frame.width / 2, y: topY - panel.frame.height)
            // Validate: at least half the pill is on-screen
            let proposed = NSRect(origin: origin, size: panel.frame.size)
            let overlap = proposed.intersection(screenFrame)
            if !overlap.isNull && overlap.width >= panel.frame.width * 0.5 {
                panel.setFrameOrigin(origin)
                return
            }
        }

        // Default: center-top, 70px from top
        panel.setFrameOrigin(NSPoint(x: screenFrame.midX - panel.frame.width / 2, y: screenFrame.maxY - 70))
    }

    private func repositionIfVisible() {
        guard let panel else { return }
        guard panel.isVisible, settingsStore.indicatorMode == .floating else { return }
        positionOnFocusedScreen()
    }

    private func saveCurrentPosition() {
        guard let panel, let screen = panel.screen, let displayID = screen.displayID else { return }
        let screenFrame = screen.visibleFrame
        let position = IndicatorScreenPosition(
            topCenterXRelative: panel.frame.midX - screenFrame.origin.x,
            topOffsetFromVisibleTop: screenFrame.maxY - panel.frame.maxY
        )
        settingsStore.saveIndicatorPosition(position, forDisplayID: displayID)
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
        guard let panel, panel.alphaValue > 0, !isHiding else { return }
        isHiding = true

        // Opacity-only fade-out — no frame scaling (prevents Capsule distortion)
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

    var body: some View {
        // Single persistent capsule container — content cross-fades inside
        ZStack {
            listeningRow
                .opacity(session.state == .listening ? 1 : 0)

            iconTextRow(
                icon: AnyView(
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                        .tint(Color(hex: "7A756E"))
                ),
                text: "Loading model...",
                color: Color(hex: "7A756E")
            )
            .opacity(session.state == .loadingModel ? 1 : 0)

            iconTextRow(
                icon: AnyView(
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                        .tint(Color(hex: "7A756E"))
                ),
                text: "Transcribing...",
                color: Color(hex: "7A756E")
            )
            .opacity(session.state == .transcribing || session.state == .processing ? 1 : 0)

            iconTextRow(
                icon: AnyView(
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "6B9E7A"))
                ),
                text: "Typing...",
                color: Color(hex: "6B9E7A")
            )
            .opacity(session.state == .injecting ? 1 : 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color(hex: "FEFCFA"))
        )
        .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
        .fixedSize(horizontal: true, vertical: true)
        .animation(.easeInOut(duration: 0.2), value: session.state)
    }

    private var listeningRow: some View {
        HStack(spacing: 10) {
            // Show only the 8 most recent levels so all bars fit — no clipping, no hidden bars
            ClassicBarsView(
                levels: Array(session.audioLevelHistory.suffix(8)),
                color: Color(hex: "C4703E"),
                maxHeight: 30,
                barSpacing: 2
            )
            .frame(width: 42, height: 30)

            Text("Listening")
                .font(.custom("Inter", size: 12).weight(.medium))
                .foregroundStyle(Color(hex: "A09A93"))
        }
    }

    private func iconTextRow(icon: AnyView, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            icon
            Text(text)
                .font(.custom("Inter", size: 12).weight(.medium))
                .foregroundStyle(color)
        }
    }
}
