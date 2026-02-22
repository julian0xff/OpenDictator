import SwiftUI

@main
struct DictavaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.dictationSession)
                .environmentObject(appDelegate.modelManager)
                .environmentObject(appDelegate.settingsStore)
                .environmentObject(appDelegate.snippetStore)
                .environmentObject(appDelegate.vocabularyStore)
                .environmentObject(appDelegate.transcriptionLogStore)
        }
        .defaultSize(width: 720, height: 480)

        Window("Dictation History", id: "history") {
            HistoryView()
                .environmentObject(appDelegate.transcriptionLogStore)
        }
        .defaultSize(width: 700, height: 600)
    }
}
