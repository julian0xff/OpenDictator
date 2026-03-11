import AVFoundation
import AppKit
import Combine

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var microphoneStatus: PermissionStatus = .notDetermined
    @Published var accessibilityStatus: PermissionStatus = .denied

    private var activateObserver: Any?

    init() {
        // Set immediately so values are available right away
        microphoneStatus = currentMicrophoneStatus()
        accessibilityStatus = currentAccessibilityStatus()

        // Refresh when the app activates (e.g. user returns from System Settings
        // after granting/revoking permissions). No polling needed.
        activateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Only refresh when OpenDictator itself activates
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
            self?.refreshStatuses()
        }
    }

    deinit {
        if let observer = activateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func refreshStatuses() {
        let mic = currentMicrophoneStatus()
        let ax = currentAccessibilityStatus()
        if Thread.isMainThread {
            microphoneStatus = mic
            accessibilityStatus = ax
        } else {
            DispatchQueue.main.async {
                self.microphoneStatus = mic
                self.accessibilityStatus = ax
            }
        }
    }

    // MARK: - Microphone

    private func currentMicrophoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    func requestMicrophone() async -> Bool {
        let result = await AVCaptureDevice.requestAccess(for: .audio)
        refreshStatuses()
        return result
    }

    // MARK: - Accessibility

    private func currentAccessibilityStatus() -> PermissionStatus {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        return trusted ? .granted : .denied
    }

    @discardableResult
    func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let result = AXIsProcessTrustedWithOptions(options)
        refreshStatuses()
        return result
    }

    // MARK: - All permissions

    var allPermissionsGranted: Bool {
        microphoneStatus == .granted && accessibilityStatus == .granted
    }
}
