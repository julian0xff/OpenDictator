import Foundation

struct CustomVoiceCommand: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var triggers: [String]
    var replacementText: String
    var isEnabled: Bool = true
}
