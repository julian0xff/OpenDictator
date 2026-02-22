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

    private var pollTimer: Timer?

    init() {
        // Set immediately so values are available right away
        microphoneStatus = currentMicrophoneStatus()
        accessibilityStatus = currentAccessibilityStatus()
        // Poll for changes since there's no system notification for accessibility
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshStatuses()
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
