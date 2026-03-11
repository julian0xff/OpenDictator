import AppKit
import SwiftUI
import Combine
import KeyboardShortcuts
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Direct reference to the AppDelegate instance.
    /// `NSApp.delegate as? AppDelegate` fails when using `@NSApplicationDelegateAdaptor`
    /// because SwiftUI wraps the delegate. Use this instead.
    static var shared: AppDelegate?

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
    private var holdToRecordRetryGeneration = 0

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openSettingsWindow()
        }
        return true
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // Safety: if both icons are hidden (e.g. crash between two @AppStorage writes),
        // restore menu bar icon to prevent the app becoming unreachable.
        if !settingsStore.showDockIcon && !settingsStore.showMenuBarIcon {
            settingsStore.showMenuBarIcon = true
        }

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
        updateLaunchAtLogin()
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

    func updateLaunchAtLogin() {
        do {
            if settingsStore.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at login: \(error.localizedDescription)")
        }
    }

    private func preloadModel() {
        Task {
            await dictationSession.preloadModel()
        }
    }

    private func setupHotkey() {
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
            guard let self, self.settingsStore.hasOpenedSettings else { return }
            self.dictationSession.toggle()
        }

        KeyboardShortcuts.onKeyDown(for: .copyLastTranscription) { [weak self] in
            guard let self, self.settingsStore.hasOpenedSettings else { return }
            guard let text = self.dictationSession.lastTranscription, !text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            NSSound(named: "Tink")?.play()
        }
    }

    private func setupHoldToRecord() {
        holdToRecordManager.updateConfiguredKeyCode(Int64(settingsStore.holdToRecordKeyCode))

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

        if settingsStore.holdToRecordEnabled && settingsStore.hasOpenedSettings {
            holdToRecordManager.isEnabled = true
            holdToRecordManager.ensureTapRunning()
            settingsStore.holdToRecordTapActive = holdToRecordManager.isTapActive
        }

        // Retry tap creation when accessibility permission is granted.
        // After a deploy, macOS may revoke trust because the binary hash changed.
        holdToRecordRetryCancellable = PermissionManager.shared.$accessibilityStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self,
                      status == .granted,
                      self.settingsStore.hasOpenedSettings,
                      self.settingsStore.holdToRecordEnabled else { return }
                self.holdToRecordManager.isEnabled = true
                if !self.holdToRecordManager.ensureTapRunning() {
                    self.retryHoldToRecordTapStartup(reason: "accessibility-granted")
                }
                self.settingsStore.holdToRecordTapActive = self.holdToRecordManager.isTapActive
            }
    }

    func updateHoldToRecord() {
        holdToRecordManager.updateConfiguredKeyCode(Int64(settingsStore.holdToRecordKeyCode))

        if settingsStore.holdToRecordEnabled {
            holdToRecordManager.isEnabled = true
            if !holdToRecordManager.ensureTapRunning() {
                retryHoldToRecordTapStartup(reason: "toggle")
            }
        } else {
            holdToRecordManager.stop()
            holdToRecordManager.isEnabled = false
        }
        settingsStore.holdToRecordTapActive = holdToRecordManager.isTapActive
    }

    /// Retries hold-to-record tap creation with increasing delays.
    /// Guards each retry against stale state (feature disabled, accessibility revoked).
    /// Uses a generation counter to cancel previous retry waves.
    private func retryHoldToRecordTapStartup(reason: String) {
        holdToRecordRetryGeneration += 1
        let generation = holdToRecordRetryGeneration

        for (i, delay) in [0.5, 1.0, 2.0].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.holdToRecordRetryGeneration == generation,
                      self.settingsStore.holdToRecordEnabled,
                      self.holdToRecordManager.isEnabled,
                      PermissionManager.shared.accessibilityStatus == .granted,
                      !self.holdToRecordManager.isTapActive else { return }
                let result = self.holdToRecordManager.ensureTapRunning()
                self.settingsStore.holdToRecordTapActive = self.holdToRecordManager.isTapActive
                if result {
                    NSLog("HoldToRecord: tap started on retry %d (%@, delay=%.1fs)", i + 1, reason, delay)
                }
            }
        }
    }

    private func checkFirstLaunch() {
        if !settingsStore.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    @objc func openSettingsWindow() {
        statusBarController?.closePopover()
        settingsStore.hasOpenedSettings = true

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
        window.title = "OpenDictator Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 720, height: 480)
        window.maxSize = NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("OpenDictatorSettings")
        if !window.setFrameUsingName("OpenDictatorSettings") {
            window.setContentSize(NSSize(width: 720, height: 480))
            window.center()
        }

        window.appearance = NSAppearance(named: .aqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 245/255, green: 241/255, blue: 236/255, alpha: 1)
        settingsWindow = window

        setupAppearanceObserver()

        NSApp.setActivationPolicy(.regular)
        currentPolicy = .regular
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openHistoryWindow() {
        statusBarController?.closePopover()
        settingsStore.hasOpenedSettings = true

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
        window.title = "OpenDictator Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 720, height: 480)
        window.maxSize = NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("OpenDictatorSettings")
        if !window.setFrameUsingName("OpenDictatorSettings") {
            window.setContentSize(NSSize(width: 720, height: 480))
            window.center()
        }

        window.appearance = NSAppearance(named: .aqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 245/255, green: 241/255, blue: 236/255, alpha: 1)
        settingsWindow = window

        setupAppearanceObserver()

        NSApp.setActivationPolicy(.regular)
        currentPolicy = .regular
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupAppearanceObserver() {
        // No-op: warm theme uses fixed colors, no appearance syncing needed.
    }

    @objc func completeOnboarding() {
        // 1. Mark onboarding complete and unlock features FIRST,
        //    so the retry subscription (holdToRecordRetryCancellable) passes
        //    its hasOpenedSettings guard when refreshStatuses() republishes .granted.
        settingsStore.hasCompletedOnboarding = true
        settingsStore.hasOpenedSettings = true

        // 2. Refresh permissions to pick up any grants made during onboarding.
        //    This republishes $accessibilityStatus which triggers the retry subscription.
        PermissionManager.shared.refreshStatuses()

        // 3. Apply provider + model to the live DictationSession.
        //    switchProvider() sets the provider and starts model load.
        //    It guards against loading FluidAudio if not downloaded.
        let language = settingsStore.selectedLanguage
        let preferred = settingsStore.preferredProvider(for: language)
        dictationSession.switchProvider(to: preferred)

        // 4. Retry hold-to-record tap now that accessibility may be granted.
        if settingsStore.holdToRecordEnabled {
            holdToRecordManager.isEnabled = true
            if !holdToRecordManager.ensureTapRunning() {
                retryHoldToRecordTapStartup(reason: "onboarding")
            }
            settingsStore.holdToRecordTapActive = holdToRecordManager.isTapActive
        }

        // 5. Open Settings window
        openSettingsWindow()
    }

    func showOnboarding() {
        guard !hasShownOnboarding else { return }
        hasShownOnboarding = true

        let onboardingView = OnboardingView(
            settingsStore: settingsStore,
            modelManager: modelManager,
            fluidAudioModelManager: fluidAudioModelManager
        )
        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to OpenDictator"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 500, height: 600))
        window.center()

        // If the user closes mid-flow, allow onboarding to re-show on next launch
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.settingsStore.hasCompletedOnboarding else { return }
            self.hasShownOnboarding = false
        }

        NSApp.setActivationPolicy(.regular)
        currentPolicy = .regular
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
