import Foundation

enum DictationState: Equatable {
    case idle
    case listening
    case transcribing
    case processing
    case injecting
    case executingCommand

    var isActive: Bool {
        self != .idle
    }

    var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .processing: return "Processing..."
        case .injecting: return "Typing..."
        case .executingCommand: return "Executing..."
        }
    }
}
