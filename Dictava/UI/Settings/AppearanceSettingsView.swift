import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var customThemeStore: CustomThemeStore
    @Environment(\.colorScheme) private var colorScheme

    // Draft state for editing built-in themes
    @State private var draftTheme: IndicatorTheme?

    // Save as new theme sheet
    @State private var showSaveAsSheet = false
    @State private var newThemeName = ""
    @State private var isNewThemeDraft = false

    // Import sheet
    @State private var showImportSheet = false
    @State private var importCode = ""
    @State private var importError: String?

    // Rename sheet
    @State private var showRenameSheet = false
    @State private var renameTarget: IndicatorTheme?
    @State private var renameText = ""

    private var activeTheme: IndicatorTheme {
        if let draft = draftTheme {
            return draft
        }
        if let custom = customThemeStore.theme(for: settingsStore.indicatorThemeName) {
            return custom
        }
        return settingsStore.currentIndicatorTheme(isDarkMode: colorScheme == .dark, customThemes: customThemeStore.themes)
    }

    private var isBuiltInSelected: Bool {
        let id = settingsStore.indicatorThemeName
        return id == "system" || IndicatorTheme.allPresets.contains(where: { $0.id == id })
    }

    private var isCustomSelected: Bool {
        customThemeStore.theme(for: settingsStore.indicatorThemeName) != nil
    }

    var body: some View {
        ScrollView {
            Form {
                Section("Theme") {
                    themeGrid
                    actionButtons
                }

                Section("Preview") {
                    indicatorPreview
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }

                Section("Customize") {
                    customControls
                }
            }
            .formStyle(.grouped)
        }
        .sheet(isPresented: $showSaveAsSheet, onDismiss: {
            if isNewThemeDraft {
                draftTheme = nil
                isNewThemeDraft = false
            }
        }) {
            saveAsSheet
        }
        .sheet(isPresented: $showImportSheet) {
            importSheet
        }
        .sheet(isPresented: $showRenameSheet) {
            renameSheet
        }
    }

    // MARK: - Theme Grid

    @ViewBuilder
    private var themeGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
            // System card — always shows midnight/frost, never the current selection
            let systemPreview = colorScheme == .dark ? IndicatorTheme.midnight : IndicatorTheme.frost
            themeCard(id: "system", label: "System", theme: systemPreview)

            ForEach(IndicatorTheme.allPresets) { preset in
                themeCard(id: preset.id, label: preset.label, theme: preset)
                    .contextMenu {
                        Button("Export Code") {
                            exportTheme(preset)
                        }
                    }
            }

            ForEach(customThemeStore.themes) { custom in
                themeCard(id: custom.id, label: custom.label, theme: custom, isCustom: true)
                    .contextMenu {
                        Button("Rename...") {
                            renameTarget = custom
                            renameText = custom.label
                            showRenameSheet = true
                        }
                        Button("Export Code") {
                            exportTheme(custom)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            deleteCustomTheme(id: custom.id)
                        }
                    }
            }

            // "Create New Theme" card
            createNewThemeCard
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var createNewThemeCard: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.secondary.opacity(0.3))
                    )

                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 32)
            .padding(.horizontal, 4)

            Text("New Theme")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .contentShape(Rectangle())
        .onTapGesture {
            createNewTheme()
        }
    }

    @ViewBuilder
    private func themeCard(id: String, label: String, theme: IndicatorTheme, isCustom: Bool = false) -> some View {
        let isSelected = settingsStore.indicatorThemeName == id
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                // Mini pill preview
                HStack(spacing: 2) {
                    ForEach(0..<8, id: \.self) { i in
                        let heights: [CGFloat] = [4, 7, 10, 14, 12, 8, 6, 3]
                        RoundedRectangle(cornerRadius: 1)
                            .fill(theme.waveformColor)
                            .frame(width: 2.5, height: heights[i])
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.backgroundColor.opacity(theme.backgroundOpacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(theme.borderColor.opacity(theme.borderOpacity), lineWidth: theme.borderWidth)
                )

                if isCustom {
                    Button {
                        deleteCustomTheme(id: id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                }
            }

            Text(label)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectTheme(id: id)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                importCode = ""
                importError = nil
                showImportSheet = true
            } label: {
                Label("Import Theme...", systemImage: "square.and.arrow.down")
            }

            Spacer()

            Button("Export Code") {
                exportTheme(activeTheme)
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var indicatorPreview: some View {
        let theme = activeTheme
        HStack(spacing: 2) {
            ForEach(0..<20, id: \.self) { i in
                let seed = Double(i)
                let height = 2 + abs(sin(seed * 0.7)) * 26
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(theme.waveformColor)
                    .frame(width: 3, height: height)
            }
        }
        .padding(.horizontal, theme.horizontalPadding)
        .padding(.vertical, theme.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .fill(theme.backgroundColor.opacity(theme.backgroundOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .stroke(theme.borderColor.opacity(theme.borderOpacity), lineWidth: theme.borderWidth)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }

    // MARK: - Customize Controls

    @ViewBuilder
    private var customControls: some View {
        let themeBinding = editableThemeBinding

        // Randomize button
        HStack {
            Button {
                randomizeCurrentTheme()
            } label: {
                Label("Randomize", systemImage: "dice.fill")
            }
            Spacer()
        }

        ColorPicker("Waveform Color", selection: Binding(
            get: { Color(hex: themeBinding.wrappedValue.waveformColorHex) },
            set: {
                var updated = themeBinding.wrappedValue
                updated.waveformColorHex = $0.toHex()
                themeBinding.wrappedValue = updated
            }
        ), supportsOpacity: false)

        ColorPicker("Background Color", selection: Binding(
            get: { Color(hex: themeBinding.wrappedValue.backgroundColorHex) },
            set: {
                var updated = themeBinding.wrappedValue
                updated.backgroundColorHex = $0.toHex()
                themeBinding.wrappedValue = updated
            }
        ), supportsOpacity: false)

        ColorPicker("Border Color", selection: Binding(
            get: { Color(hex: themeBinding.wrappedValue.borderColorHex) },
            set: {
                var updated = themeBinding.wrappedValue
                updated.borderColorHex = $0.toHex()
                themeBinding.wrappedValue = updated
            }
        ), supportsOpacity: false)

        HStack {
            Text("Corner Radius")
            Slider(value: themeBinding.cornerRadius, in: 8...30, step: 1)
            Text("\(Int(themeBinding.wrappedValue.cornerRadius))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
        }

        HStack {
            Text("Border Width")
            Slider(value: themeBinding.borderWidth, in: 0...3, step: 0.5)
            Text(String(format: "%.1f", themeBinding.wrappedValue.borderWidth))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
        }

        HStack {
            Text("Background Opacity")
            Slider(value: themeBinding.backgroundOpacity, in: 0.5...1.0, step: 0.05)
            Text(String(format: "%.0f%%", themeBinding.wrappedValue.backgroundOpacity * 100))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }

        HStack {
            Text("Padding")
            Slider(value: themeBinding.horizontalPadding, in: 8...24, step: 1)
            Text("\(Int(themeBinding.wrappedValue.horizontalPadding))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
        }

        // Save as new theme — always visible
        Button("Save as New Theme...") {
            let source = activeTheme
            newThemeName = isCustomSelected ? "\(source.label) Copy" : source.label
            showSaveAsSheet = true
        }
    }

    /// Returns a binding that routes edits to either `draftTheme` (built-in) or `customThemeStore` (custom).
    /// Returns a binding that routes edits to `draftTheme` (new theme or built-in) or `customThemeStore` (custom).
    /// New-theme draft takes priority so edits never leak into an existing custom theme.
    private var editableThemeBinding: Binding<IndicatorTheme> {
        if isNewThemeDraft {
            return Binding(
                get: { draftTheme ?? IndicatorTheme.randomized() },
                set: { newValue in draftTheme = newValue }
            )
        }
        if isCustomSelected, let custom = customThemeStore.theme(for: settingsStore.indicatorThemeName) {
            return Binding(
                get: {
                    customThemeStore.theme(for: settingsStore.indicatorThemeName) ?? custom
                },
                set: { newValue in
                    customThemeStore.updateTheme(newValue)
                }
            )
        } else {
            // Built-in: route through draftTheme
            return Binding(
                get: {
                    if let draft = draftTheme {
                        return draft
                    }
                    return settingsStore.currentIndicatorTheme(isDarkMode: colorScheme == .dark, customThemes: customThemeStore.themes)
                },
                set: { newValue in
                    draftTheme = newValue
                }
            )
        }
    }

    // MARK: - Save As Sheet

    private var saveAsSheet: some View {
        VStack(spacing: 16) {
            Text("Save as New Theme")
                .font(.headline)

            TextField("Theme Name", text: $newThemeName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            HStack(spacing: 12) {
                Button("Cancel") {
                    showSaveAsSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveAsNewTheme()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newThemeName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
    }

    // MARK: - Import Sheet

    private var importSheet: some View {
        VStack(spacing: 16) {
            Text("Import Theme")
                .font(.headline)

            TextField("Paste theme code (DT1:...)", text: $importCode)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)

            if let preview = IndicatorTheme.fromCode(importCode) {
                // Live preview
                HStack(spacing: 2) {
                    ForEach(0..<8, id: \.self) { i in
                        let heights: [CGFloat] = [4, 7, 10, 14, 12, 8, 6, 3]
                        RoundedRectangle(cornerRadius: 1)
                            .fill(preview.waveformColor)
                            .frame(width: 2.5, height: heights[i])
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(preview.backgroundColor.opacity(preview.backgroundOpacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(preview.borderColor.opacity(preview.borderOpacity), lineWidth: preview.borderWidth)
                )

                Text(preview.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !importCode.isEmpty {
                Text("Invalid theme code")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    showImportSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Import") {
                    importTheme()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(IndicatorTheme.fromCode(importCode) == nil)
            }
        }
        .padding(24)
    }

    // MARK: - Rename Sheet

    private var renameSheet: some View {
        VStack(spacing: 16) {
            Text("Rename Theme")
                .font(.headline)

            TextField("Theme Name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            HStack(spacing: 12) {
                Button("Cancel") {
                    showRenameSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    if var target = renameTarget {
                        target.label = renameText.trimmingCharacters(in: .whitespaces)
                        customThemeStore.updateTheme(target)
                    }
                    showRenameSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
    }

    // MARK: - Actions

    private func selectTheme(id: String) {
        settingsStore.indicatorThemeName = id
        draftTheme = nil
    }

    private func createNewTheme() {
        draftTheme = IndicatorTheme.randomized()
        isNewThemeDraft = true
        newThemeName = ""
        showSaveAsSheet = true
    }

    private func randomizeCurrentTheme() {
        let random = IndicatorTheme.randomized()
        var current = editableThemeBinding.wrappedValue
        current.waveformColorHex = random.waveformColorHex
        current.backgroundColorHex = random.backgroundColorHex
        current.borderColorHex = random.borderColorHex
        current.cornerRadius = random.cornerRadius
        current.borderWidth = random.borderWidth
        current.borderOpacity = random.borderOpacity
        current.horizontalPadding = random.horizontalPadding
        current.verticalPadding = random.verticalPadding
        current.backgroundOpacity = random.backgroundOpacity
        editableThemeBinding.wrappedValue = current
    }

    private func saveAsNewTheme() {
        let source = activeTheme
        var newTheme = source
        newTheme.id = UUID().uuidString
        newTheme.label = newThemeName.trimmingCharacters(in: .whitespaces)
        newTheme.isBuiltIn = false
        customThemeStore.addTheme(newTheme)
        settingsStore.indicatorThemeName = newTheme.id
        draftTheme = nil
        isNewThemeDraft = false
        showSaveAsSheet = false
    }

    private func importTheme() {
        guard var theme = IndicatorTheme.fromCode(importCode) else { return }
        theme.isBuiltIn = false
        customThemeStore.addTheme(theme)
        settingsStore.indicatorThemeName = theme.id
        showImportSheet = false
    }

    private func deleteCustomTheme(id: String) {
        if settingsStore.indicatorThemeName == id {
            settingsStore.indicatorThemeName = "system"
        }
        customThemeStore.removeTheme(id: id)
    }

    private func exportTheme(_ theme: IndicatorTheme) {
        guard let code = theme.exportCode() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }
}
