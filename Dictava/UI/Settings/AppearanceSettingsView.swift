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
                Section {
                    indicatorModePicker
                } header: {
                    SettingsSectionHeader(icon: "display", title: "Indicator Mode", color: .cyan)
                }

                Section {
                    indicatorPreview
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } header: {
                    SettingsSectionHeader(icon: "eye", title: "Preview", color: .blue)
                }

                if settingsStore.indicatorMode == .floating {
                    Section {
                        themeGrid
                        actionButtons
                    } header: {
                        SettingsSectionHeader(icon: "paintbrush", title: "Theme", color: .pink)
                    }

                    Section {
                        visualizationStylePicker
                    } header: {
                        SettingsSectionHeader(icon: "waveform", title: "Visualization Style", color: .purple)
                    }

                    Section {
                        indicatorSizePicker
                    } header: {
                        SettingsSectionHeader(icon: "arrow.up.left.and.arrow.down.right", title: "Widget Size", color: .teal)
                    }

                    Section {
                        customControls
                    } header: {
                        SettingsSectionHeader(icon: "slider.horizontal.3", title: "Customize", color: .orange)
                    }
                }

                if settingsStore.indicatorMode == .notch {
                    Section {
                        notchCustomizeControls
                    } header: {
                        SettingsSectionHeader(icon: "slider.horizontal.3", title: "Customize", color: .orange)
                    }
                }
            }
            .formStyle(.grouped)
            .animation(.easeInOut(duration: 0.2), value: settingsStore.indicatorModeRaw)
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

    // MARK: - Indicator Mode Picker

    @ViewBuilder
    private var indicatorModePicker: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(IndicatorMode.allCases) { mode in
                modeCard(mode)
            }
        }
        .padding(.vertical, 4)

        if settingsStore.indicatorMode == .notch {
            if !NSScreen.screens.contains(where: { $0.hasNotch }) {
                InfoBanner(.info, "No notch detected. A virtual notch-like shape will appear at the top center of the screen.")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Expansion Style")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    ForEach(NotchExpansionStyle.allCases) { style in
                        expansionStyleCard(style)
                    }
                }
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Animation Speed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { settingsStore.notchAnimationSpeed },
                    set: { settingsStore.notchAnimationSpeed = $0 }
                )) {
                    ForEach(NotchAnimationSpeed.allCases) { speed in
                        Text(speed.displayName).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func modeCard(_ mode: IndicatorMode) -> some View {
        let isSelected = settingsStore.indicatorMode == mode
        VStack(spacing: 6) {
            Image(systemName: mode.sfSymbol)
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(height: 28)

            Text(mode.displayName)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
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
            withAnimation(.easeInOut(duration: 0.2)) {
                settingsStore.indicatorMode = mode
            }
        }
    }

    @ViewBuilder
    private func expansionStyleCard(_ style: NotchExpansionStyle) -> some View {
        let isSelected = settingsStore.notchExpansionStyle == style
        VStack(spacing: 6) {
            Image(systemName: style.sfSymbol)
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(height: 28)

            Text(style.displayName)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
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
            settingsStore.notchExpansionStyle = style
        }
    }

    // MARK: - Preview

    private static let sampleHistory: [Float] = [
        0.1, 0.3, 0.5, 0.8, 0.9, 0.7, 0.6, 0.4,
        0.5, 0.7, 0.9, 0.8, 0.6, 0.4, 0.3, 0.5,
        0.7, 0.8, 0.6, 0.3
    ]
    private static let sampleLevel: Float = 0.65

    @ViewBuilder
    private var indicatorPreview: some View {
        if settingsStore.indicatorMode == .notch {
            notchPreview
        } else {
            floatingPreview
        }
    }

    @ViewBuilder
    private var floatingPreview: some View {
        let theme = activeTheme
        let style = settingsStore.waveformStyle
        let metrics = IndicatorSizeMetrics.metrics(forScale: settingsStore.indicatorScale)

        WaveformVisualizationView(
            style: style,
            level: Self.sampleLevel,
            history: Self.sampleHistory,
            color: theme.waveformColor,
            metrics: metrics
        )
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
        .fixedSize()
    }

    @ViewBuilder
    private var notchPreview: some View {
        let previewNotchWidth: CGFloat = 160
        let style = settingsStore.notchExpansionStyle
        let previewMetrics = IndicatorSizeMetrics(visualizationWidth: min(previewNotchWidth - 20, 100), visualizationHeight: 22)

        let expandedWidth: CGFloat = {
            switch style {
            case .down: return previewNotchWidth + 20
            case .horizontal: return previewNotchWidth + 120
            case .both: return previewNotchWidth + 100
            }
        }()
        let expandedHeight: CGFloat = {
            switch style {
            case .down: return 68
            case .horizontal: return 32
            case .both: return 68
            }
        }()

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(topCornerRadius: 14, bottomCornerRadius: 20)
                    .fill(.black)
                    .frame(width: expandedWidth, height: expandedHeight)

                // Preview content by style
                switch style {
                case .down:
                    VStack(spacing: 0) {
                        Spacer().frame(height: 34)
                        WaveformVisualizationView(
                            style: .glowOrb,
                            level: Self.sampleLevel,
                            history: Self.sampleHistory,
                            color: settingsStore.notchGlowColor,
                            metrics: previewMetrics
                        )
                    }
                    .frame(width: expandedWidth, height: expandedHeight)

                case .horizontal:
                    HStack(spacing: 0) {
                        Circle()
                            .fill(settingsStore.notchGlowColor.opacity(0.9))
                            .frame(width: 10, height: 10)
                            .shadow(color: settingsStore.notchGlowColor.opacity(0.6), radius: 4)
                            .frame(width: 60)
                        Spacer().frame(width: previewNotchWidth)
                        HStack(spacing: 4) {
                            Circle().fill(.red).frame(width: 5, height: 5)
                            Text("0:05")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 60)
                    }
                    .frame(width: expandedWidth, height: expandedHeight)

                case .both:
                    VStack(spacing: 0) {
                        Spacer().frame(height: 34)
                        WaveformVisualizationView(
                            style: .glowOrb,
                            level: Self.sampleLevel,
                            history: Self.sampleHistory,
                            color: settingsStore.notchGlowColor,
                            metrics: previewMetrics
                        )
                    }
                    .frame(width: expandedWidth, height: expandedHeight)
                }
            }
        }
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

    // MARK: - Notch Customize Controls

    @ViewBuilder
    private var notchCustomizeControls: some View {
        ColorPicker("Glow Color", selection: Binding(
            get: { settingsStore.notchGlowColor },
            set: { settingsStore.notchGlowColor = $0 }
        ), supportsOpacity: false)
    }

    // MARK: - Visualization Style Picker

    @ViewBuilder
    private var visualizationStylePicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
            ForEach(WaveformStyle.allCases) { style in
                styleCard(style)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func styleCard(_ style: WaveformStyle) -> some View {
        let isSelected = settingsStore.waveformStyle == style
        VStack(spacing: 6) {
            Image(systemName: style.sfSymbol)
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(height: 28)

            Text(style.displayName)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
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
            settingsStore.waveformStyleRaw = style.rawValue
        }
    }

    // MARK: - Widget Size Slider

    @ViewBuilder
    private var indicatorSizePicker: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Widget Size")
                Spacer()
            }
            HStack(spacing: 8) {
                Image(systemName: "minus")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $settingsStore.indicatorScale, in: 0...1, step: 0.05)
                Image(systemName: "plus")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
        .frame(width: 320)
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
        .frame(width: 420)
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
        .frame(width: 320)
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
