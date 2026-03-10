import AppKit
import SwiftUI
import Combine
import KeyboardShortcuts
import ServiceManagement

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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openSettingsWindow()
        }
        return true
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
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
                if !self.holdToRecordManager.isTapActive {
                    NSLog("HoldToRecord: Accessibility granted, ensuring tap is running")
                }
                self.holdToRecordManager.isEnabled = true
                self.holdToRecordManager.ensureTapRunning()
                self.settingsStore.holdToRecordTapActive = self.holdToRecordManager.isTapActive
            }
    }

    func updateHoldToRecord() {
        holdToRecordManager.updateConfiguredKeyCode(Int64(settingsStore.holdToRecordKeyCode))

        if settingsStore.holdToRecordEnabled {
            holdToRecordManager.isEnabled = true
            if !holdToRecordManager.ensureTapRunning() {
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

    func showOnboarding() {
        guard !hasShownOnboarding else { return }
        hasShownOnboarding = true

        let onboardingView = OnboardingView(settingsStore: settingsStore, modelManager: modelManager)
        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to OpenDictator"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 500, height: 600))
        window.center()
        NSApp.setActivationPolicy(.regular)
        currentPolicy = .regular
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
