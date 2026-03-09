import Foundation

enum DictationState: Equatable {
    case idle
    case loadingModel
    case listening
    case transcribing
    case processing
    case injecting

    var isActive: Bool {
        self != .idle
    }

    var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .loadingModel: return "Loading model..."
        case .listening: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .processing: return "Processing..."
        case .injecting: return "Typing..."
        }
    }
}
