import AppKit
import SwiftUI
import Combine

// MARK: - Shared Observable State

/// Shared state object that the view observes. The window manager toggles `isExpanded`;
/// SwiftUI animates the transition because the view identity is preserved (never replaced).
@MainActor
final class NotchIndicatorState: ObservableObject {
    @Published var isExpanded = false
}

// MARK: - Notch Panel (subclass like boring.notch)

/// NSPanel subclass that never steals focus, matching boring.notch's BoringNotchWindow.
class NotchPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)

        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        hasShadow = false
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        appearance = NSAppearance(named: .darkAqua)

        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Notch Indicator Window Manager

@MainActor
final class NotchIndicatorWindow {
    private var panel: NotchPanel?
    private var cancellables = Set<AnyCancellable>()
    private let settingsStore: SettingsStore
    private let dictationSession: DictationSession
    private let state = NotchIndicatorState()
    private var collapseWorkItem: DispatchWorkItem?
    private var pendingExpandWorkItem: DispatchWorkItem?
    private var lastDisplayID: CGDirectDisplayID?

    // Fallback dimensions for non-notch screens
    private let fallbackNotchWidth: CGFloat = 200
    private let fallbackNotchHeight: CGFloat = 32

    init(dictationSession: DictationSession, settingsStore: SettingsStore, customThemeStore: CustomThemeStore) {
        self.dictationSession = dictationSession
        self.settingsStore = settingsStore

        dictationSession.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state.isActive && self.settingsStore.indicatorMode == .notch {
                    self.expand()
                } else {
                    self.collapse()
                }
            }
            .store(in: &cancellables)
    }

    private func createPanelIfNeeded(for screen: NSScreen = .focused) {
        guard panel == nil else { return }

        let hasNotch = screen.hasNotch
        let notchWidth = screen.notchWidth ?? fallbackNotchWidth
        let notchHeight = hasNotch ? screen.notchHeight : fallbackNotchHeight

        // Fixed panel size — large enough for the biggest expansion style.
        // The SwiftUI view handles its own sizing inside this fixed frame.
        let panelWidth = notchWidth + 200
        let panelHeight = notchHeight + 60

        let contentView = NotchIndicatorView(
            session: dictationSession,
            settingsStore: settingsStore,
            state: state,
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            hasPhysicalNotch: hasNotch
        )

        let hosting = NSHostingView(rootView: contentView)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Container that pins the hosting view to the top center
        let container = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear
        container.addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            hosting.widthAnchor.constraint(equalToConstant: panelWidth),
            hosting.heightAnchor.constraint(equalToConstant: panelHeight),
        ])

        panel.contentView = container

        // Position: top edge of panel = top edge of screen (flush with physical screen top)
        let screenFrame = screen.frame
        let x = screenFrame.origin.x + (screenFrame.width / 2) - panelWidth / 2
        let y = screenFrame.origin.y + screenFrame.height - panelHeight
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        self.panel = panel
    }

    private func expand() {
        guard !state.isExpanded else { return }

        // Cancel any pending collapse/orderOut
        collapseWorkItem?.cancel()
        collapseWorkItem = nil

        let targetScreen = NSScreen.focused
        let targetDisplayID = targetScreen.displayID

        // If screen changed, tear down panel so it's recreated with correct notch dimensions
        if let targetDisplayID, targetDisplayID != lastDisplayID, panel != nil {
            panel?.orderOut(nil)
            panel = nil
        }

        let isFirstShow = (panel == nil)
        createPanelIfNeeded(for: targetScreen)
        lastDisplayID = targetDisplayID

        if isFirstShow {
            panel?.alphaValue = 0
            panel?.orderFront(nil)
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.state.isExpanded = true
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    self.panel?.animator().alphaValue = 1
                }
                self.pendingExpandWorkItem = nil
            }
            pendingExpandWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        } else {
            panel?.alphaValue = 1
            panel?.orderFront(nil)
            state.isExpanded = true
        }
    }

    private func collapse() {
        pendingExpandWorkItem?.cancel()
        pendingExpandWorkItem = nil
        guard state.isExpanded else { return }

        state.isExpanded = false

        // Delay orderOut to let the collapse animation complete
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.state.isExpanded else { return }
            self.panel?.orderOut(nil)
        }
        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
}
