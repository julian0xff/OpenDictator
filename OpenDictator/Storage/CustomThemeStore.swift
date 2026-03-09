import SwiftUI

final class CustomThemeStore: ObservableObject {
    @Published var themes: [IndicatorTheme] = []

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("OpenDictator", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("custom_themes.json")
    }()

    init() {
        load()
        migrateFromUserDefaults()
    }

    // MARK: - Persistence

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([IndicatorTheme].self, from: data) else {
            return
        }
        themes = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(themes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - CRUD

    func addTheme(_ theme: IndicatorTheme) {
        themes.append(theme)
        save()
    }

    func updateTheme(_ theme: IndicatorTheme) {
        if let index = themes.firstIndex(where: { $0.id == theme.id }) {
            themes[index] = theme
            save()
        }
    }

    func removeTheme(id: String) {
        themes.removeAll { $0.id == id }
        save()
    }

    func theme(for id: String) -> IndicatorTheme? {
        themes.first { $0.id == id }
    }

    // MARK: - Migration from old single custom theme

    private func migrateFromUserDefaults() {
        let key = "customIndicatorThemeData"
        guard let data = UserDefaults.standard.data(forKey: key), !data.isEmpty,
              var theme = try? JSONDecoder().decode(IndicatorTheme.self, from: data) else {
            return
        }

        // Assign a fresh UUID and mark as custom
        theme.id = UUID().uuidString
        theme.isBuiltIn = false
        if theme.label == "Custom" {
            theme.label = "My Theme"
        }

        themes.append(theme)
        save()

        // Update the selected theme name if it was "custom"
        if UserDefaults.standard.string(forKey: "indicatorThemeName") == "custom" {
            UserDefaults.standard.set(theme.id, forKey: "indicatorThemeName")
        }

        // Remove old key
        UserDefaults.standard.removeObject(forKey: key)
    }
}
