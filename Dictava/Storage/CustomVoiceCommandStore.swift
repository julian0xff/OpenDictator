import SwiftUI

final class CustomVoiceCommandStore: ObservableObject {
    @Published var commands: [CustomVoiceCommand] = []

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Dictava", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("custom_voice_commands.json")
    }()

    init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CustomVoiceCommand].self, from: data) else {
            return
        }
        commands = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func addCommand(_ command: CustomVoiceCommand) {
        commands.append(command)
        save()
    }

    func removeCommand(at offsets: IndexSet) {
        commands.remove(atOffsets: offsets)
        save()
    }

    func removeCommand(id: UUID) {
        commands.removeAll { $0.id == id }
        save()
    }

    func updateCommand(_ command: CustomVoiceCommand) {
        if let index = commands.firstIndex(where: { $0.id == command.id }) {
            commands[index] = command
            save()
        }
    }
}
