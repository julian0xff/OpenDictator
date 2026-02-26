import AppKit
import SwiftUI
import Combine
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settingsStore = SettingsStore()
    let modelManager = ModelManager()
    let fluidAudioModelManager = FluidAudioModelManager()
    let snippetStore = SnippetStore()
    let vocabularyStore = VocabularyStore()
    let transcriptionLogStore = TranscriptionLogStore()
    let customThemeStore = CustomThemeStore()
    lazy var dictationSession = DictationSession(
        settingsStore: settingsStore,
        modelManager: modelManager,
        fluidAudioModelManager: fluidAudioModelManager,
        snippetStore: snippetStore,
        vocabularyStore: vocabularyStore,
        transcriptionLogStore: transcriptionLogStore
    )

    let holdToRecordManager = HoldToRecordManager()

    private var statusBarController: StatusBarController?
    private var indicatorWindow: DictationIndicatorWindow?
    private var notchIndicatorWindow: NotchIndicatorWindow?
    private var settingsWindow: NSWindow?
    private var hasShownOnboarding = false
    private var windowObservers: [NSObjectProtocol] = []
    private var currentPolicy: NSApplication.ActivationPolicy = .accessory
    private var holdToRecordRetryCancellable: AnyCancellable?

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
            fluidAudioModelManager: fluidAudioModelManager,
            settingsStore: settingsStore,
            transcriptionLogStore: transcriptionLogStore
        )

        indicatorWindow = DictationIndicatorWindow(dictationSession: dictationSession, settingsStore: settingsStore, customThemeStore: customThemeStore)
        notchIndicatorWindow = NotchIndicatorWindow(dictationSession: dictationSession, settingsStore: settingsStore, customThemeStore: customThemeStore)

        settingsStore.migrateModelNameIfNeeded()
        setupHotkey()
        setupHoldToRecord()
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

    private func setupHoldToRecord() {
        holdToRecordManager.configuredKeyCode = Int64(settingsStore.holdToRecordKeyCode)

        holdToRecordManager.onStartDictation = { [weak self] in
            guard let self, self.dictationSession.state == .idle else { return }
            self.holdToRecordManager.holdSessionActive = true
            self.dictationSession.startDictation()
        }

        holdToRecordManager.onStopDictation = { [weak self] in
            guard let self, self.holdToRecordManager.holdSessionActive else { return }
            self.holdToRecordManager.holdSessionActive = false
            self.dictationSession.holdRelease()
        }

        if settingsStore.holdToRecordEnabled {
            holdToRecordManager.isEnabled = true
            holdToRecordManager.start()
            settingsStore.holdToRecordTapActive = holdToRecordManager.isTapActive
        }

        // Retry tap creation when accessibility permission is granted.
        // After a deploy, macOS may revoke trust because the binary hash changed.
        holdToRecordRetryCancellable = PermissionManager.shared.$accessibilityStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self,
                      status == .granted,
                      self.settingsStore.holdToRecordEnabled,
                      !self.holdToRecordManager.isTapActive else { return }
                NSLog("HoldToRecord: Accessibility granted, retrying tap creation")
                self.holdToRecordManager.isEnabled = true
                self.holdToRecordManager.start()
                self.settingsStore.holdToRecordTapActive = self.holdToRecordManager.isTapActive
            }
    }

    func updateHoldToRecord() {
        holdToRecordManager.configuredKeyCode = Int64(settingsStore.holdToRecordKeyCode)

        if settingsStore.holdToRecordEnabled {
            holdToRecordManager.isEnabled = true
            if !holdToRecordManager.start() {
                NSLog("HoldToRecord: Tap creation failed on toggle — will retry when accessibility is granted")
            }
        } else {
            holdToRecordManager.stop()
            holdToRecordManager.isEnabled = false
        }
        settingsStore.holdToRecordTapActive = holdToRecordManager.isTapActive
    }

    private func checkFirstLaunch() {
        if !settingsStore.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    @objc func openSettingsWindow() {
        if let existing = settingsWindow {
            NSApp.setActivationPolicy(.regular)
            currentPolicy = .regular
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView()
            .environmentObject(dictationSession)
            .environmentObject(modelManager)
            .environmentObject(fluidAudioModelManager)
            .environmentObject(settingsStore)
            .environmentObject(snippetStore)
            .environmentObject(vocabularyStore)
            .environmentObject(transcriptionLogStore)
            .environmentObject(customThemeStore)

        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "Dictava Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 720, height: 480)
        window.maxSize = NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DictavaSettings")
        if !window.setFrameUsingName("DictavaSettings") {
            window.setContentSize(NSSize(width: 720, height: 480))
            window.center()
        }

        settingsWindow = window

        // Defer showing to let SwiftUI lay out
        DispatchQueue.main.async { [self] in
            NSApp.setActivationPolicy(.regular)
            currentPolicy = .regular
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func openHistoryWindow() {
        if let existing = settingsWindow {
            NSApp.setActivationPolicy(.regular)
            currentPolicy = .regular
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(initialSection: .history)
            .environmentObject(dictationSession)
            .environmentObject(modelManager)
            .environmentObject(fluidAudioModelManager)
            .environmentObject(settingsStore)
            .environmentObject(snippetStore)
            .environmentObject(vocabularyStore)
            .environmentObject(transcriptionLogStore)
            .environmentObject(customThemeStore)

        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "Dictava Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 720, height: 480)
        window.maxSize = NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DictavaSettings")
        if !window.setFrameUsingName("DictavaSettings") {
            window.setContentSize(NSSize(width: 720, height: 480))
            window.center()
        }

        settingsWindow = window

        // Defer showing to let SwiftUI lay out
        DispatchQueue.main.async { [self] in
            NSApp.setActivationPolicy(.regular)
            currentPolicy = .regular
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
        NSApp.setActivationPolicy(.regular)
        currentPolicy = .regular
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
