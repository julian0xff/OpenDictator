import AppKit
import SwiftUI
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settingsStore = SettingsStore()
    let modelManager = ModelManager()
    let snippetStore = SnippetStore()
    let vocabularyStore = VocabularyStore()
    let transcriptionLogStore = TranscriptionLogStore()
    lazy var dictationSession = DictationSession(
        settingsStore: settingsStore,
        modelManager: modelManager,
        snippetStore: snippetStore,
        vocabularyStore: vocabularyStore,
        transcriptionLogStore: transcriptionLogStore
    )

    private var statusBarController: StatusBarController?
    private var indicatorWindow: DictationIndicatorWindow?
    private var hasShownOnboarding = false
    private var windowObservers: [NSObjectProtocol] = []
    private var currentPolicy: NSApplication.ActivationPolicy = .accessory

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set activation policy as early as possible to minimize dock icon flash
        let policy: NSApplication.ActivationPolicy = settingsStore.showDockIcon ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
        currentPolicy = policy
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(
            dictationSession: dictationSession,
            modelManager: modelManager,
            settingsStore: settingsStore,
            transcriptionLogStore: transcriptionLogStore
        )

        indicatorWindow = DictationIndicatorWindow(dictationSession: dictationSession)

        setupHotkey()
        setupWindowObservers()
        checkFirstLaunch()
        preloadModel()
    }

    private func setupWindowObservers() {
        let becomeKey = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateDockIconPolicy()
        }
        let willClose = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Track which window is closing so we can exclude it from the check
            let closingWindow = notification.object as? NSWindow
            DispatchQueue.main.async {
                self?.updateDockIconPolicy(excluding: closingWindow)
            }
        }
        windowObservers = [becomeKey, willClose]
    }

    func updateDockIconPolicy(excluding closingWindow: NSWindow? = nil) {
        let desiredPolicy: NSApplication.ActivationPolicy

        if settingsStore.showDockIcon {
            desiredPolicy = .regular
        } else {
            let hasVisibleWindow = NSApp.windows.contains { window in
                window !== closingWindow
                && window.isVisible
                && !(window is NSPanel)
                && window.level == .normal
            }
            desiredPolicy = hasVisibleWindow ? .regular : .accessory
        }

        guard desiredPolicy != currentPolicy else { return }
        NSApp.setActivationPolicy(desiredPolicy)
        currentPolicy = desiredPolicy

        if desiredPolicy == .regular {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func preloadModel() {
        Task {
            await dictationSession.preloadModel()
        }
    }

    private func setupHotkey() {
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
            self?.dictationSession.toggle()
        }

        KeyboardShortcuts.onKeyDown(for: .copyLastTranscription) { [weak self] in
            guard let text = self?.dictationSession.lastTranscription, !text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            NSSound(named: "Tink")?.play()
        }
    }

    private func checkFirstLaunch() {
        if !settingsStore.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    func showOnboarding() {
        guard !hasShownOnboarding else { return }
        hasShownOnboarding = true

        let onboardingView = OnboardingView(settingsStore: settingsStore, modelManager: modelManager)
        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Dictava"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 500, height: 600))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
