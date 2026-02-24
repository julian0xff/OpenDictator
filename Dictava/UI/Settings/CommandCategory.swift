import SwiftUI

enum CommandCategory: String, CaseIterable {
    case editing = "Editing"
    case formatting = "Formatting"
    case session = "Session"
    case ai = "AI"

    var icon: String {
        switch self {
        case .editing: return "pencil"
        case .formatting: return "textformat"
        case .session: return "stop.circle"
        case .ai: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .editing: return .blue
        case .formatting: return .purple
        case .session: return .red
        case .ai: return .orange
        }
    }
}
