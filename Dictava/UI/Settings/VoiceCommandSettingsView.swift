import SwiftUI

private struct TriggerEditing: Identifiable {
    let id = UUID()
    let commandName: String
}

struct VoiceCommandSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var customVoiceCommandStore: CustomVoiceCommandStore

    @State private var editingTriggers: TriggerEditing?
    @State private var triggerEditText = ""
    @State private var showAddCustom = false
    @State private var editingCustomCommand: CustomVoiceCommand?
    @State private var customName = ""
    @State private var customTriggers = ""
    @State private var customReplacement = ""

    private var definitionsByCategory: [(CommandCategory, [VoiceCommandDefinition])] {
        CommandCategory.allCases.compactMap { category in
            let defs = VoiceCommandParser.allDefinitions.filter { $0.category == category }
            return defs.isEmpty ? nil : (category, defs)
        }
    }

    var body: some View {
        ScrollView {
            Form {
                InfoBanner(.info, "Say these phrases at the end of your dictation to trigger actions. Commands are detected after you stop speaking.")

                ForEach(definitionsByCategory, id: \.0) { category, definitions in
                    Section {
                        ForEach(definitions, id: \.name) { definition in
                            builtInCommandRow(definition, isAI: category == .ai)
                        }
                    } header: {
                        SettingsSectionHeader(
                            icon: category.icon,
                            title: category.rawValue,
                            color: category.color
                        )
                    }
                }

                Section {
                    Button {
                        customName = ""
                        customTriggers = ""
                        customReplacement = ""
                        editingCustomCommand = nil
                        showAddCustom = true
                    } label: {
                        Label("Add Custom Command", systemImage: "plus")
                    }

                    if customVoiceCommandStore.commands.isEmpty {
                        EmptyStateView(
                            icon: "command",
                            title: "No custom commands",
                            message: "Create commands that replace trigger phrases with custom text."
                        )
                    }

                    ForEach(customVoiceCommandStore.commands) { command in
                        customCommandRow(command)
                    }
                } header: {
                    SettingsSectionHeader(icon: "star", title: "Custom", color: .mint)
                }
            }
            .formStyle(.grouped)
        }
        .sheet(item: $editingTriggers) { editing in
            triggerEditorSheet(for: editing.commandName)
        }
        .sheet(isPresented: $showAddCustom) {
            customCommandEditor
        }
    }

    // MARK: - Built-in Command Row

    @ViewBuilder
    private func builtInCommandRow(_ definition: VoiceCommandDefinition, isAI: Bool) -> some View {
        let enabled = Binding(
            get: { settingsStore.isVoiceCommandEnabled(definition.name) },
            set: { settingsStore.setVoiceCommandEnabled(definition.name, enabled: $0) }
        )

        HStack(spacing: 10) {
            Toggle("", isOn: enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(definition.name.replacingOccurrences(of: "llmRewrite.", with: ""))
                        .fontWeight(.medium)
                    if isAI {
                        Text("Coming Soon")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.secondary))
                    }
                }

                Text(definition.actionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let triggers = settingsStore.effectiveTriggers(for: definition.name, defaults: definition.triggers)
                HStack(spacing: 4) {
                    ForEach(triggers, id: \.self) { trigger in
                        Text(trigger)
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            Button {
                let triggers = settingsStore.effectiveTriggers(for: definition.name, defaults: definition.triggers)
                triggerEditText = triggers.joined(separator: ", ")
                editingTriggers = TriggerEditing(commandName: definition.name)
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Edit trigger phrases")
        }
        .padding(.vertical, 2)
    }

    // MARK: - Custom Command Row

    @ViewBuilder
    private func customCommandRow(_ command: CustomVoiceCommand) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { command.isEnabled },
                set: { newValue in
                    var updated = command
                    updated.isEnabled = newValue
                    customVoiceCommandStore.updateCommand(updated)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 4) {
                Text(command.name)
                    .fontWeight(.medium)

                Text(command.replacementText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    ForEach(command.triggers, id: \.self) { trigger in
                        Text(trigger)
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.mint.opacity(0.1))
                            .foregroundStyle(.mint)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            Button {
                customName = command.name
                customTriggers = command.triggers.joined(separator: ", ")
                customReplacement = command.replacementText
                editingCustomCommand = command
                showAddCustom = true
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                customVoiceCommandStore.removeCommand(id: command.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Trigger Editor Sheet

    private func triggerEditorSheet(for commandName: String) -> some View {
        let definition = VoiceCommandParser.allDefinitions.first(where: { $0.name == commandName })

        return VStack(spacing: 16) {
            Text("Edit Trigger Phrases")
                .font(.headline)

            Text("Separate multiple triggers with commas.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Trigger phrases", text: $triggerEditText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)

            HStack(spacing: 12) {
                if settingsStore.hasTriggerOverrides(for: commandName) {
                    Button("Reset to Default") {
                        settingsStore.setTriggerOverrides(nil, for: commandName)
                        editingTriggers = nil
                    }
                }

                Spacer()

                Button("Cancel") {
                    editingTriggers = nil
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    let triggers = triggerEditText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                        .filter { !$0.isEmpty }

                    guard !triggers.isEmpty else {
                        editingTriggers = nil
                        return
                    }

                    if triggers == definition?.triggers {
                        settingsStore.setTriggerOverrides(nil, for: commandName)
                    } else {
                        settingsStore.setTriggerOverrides(triggers, for: commandName)
                    }
                    editingTriggers = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled({
                    let parsed = triggerEditText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    return parsed.isEmpty
                }())
            }
        }
        .padding(24)
    }

    // MARK: - Custom Command Editor

    private var customCommandEditor: some View {
        VStack(spacing: 16) {
            Text(editingCustomCommand == nil ? "New Custom Command" : "Edit Custom Command")
                .font(.headline)

            TextField("Command name", text: $customName)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Trigger phrases (comma-separated):")
                    .font(.caption)
                TextField("e.g. sign off, signature", text: $customTriggers)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Replacement text:")
                    .font(.caption)
                TextEditor(text: $customReplacement)
                    .font(.body)
                    .frame(minHeight: 80)
                    .border(.quaternary)
            }

            HStack {
                Button("Cancel") { showAddCustom = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let triggers = customTriggers
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                        .filter { !$0.isEmpty }

                    if var existing = editingCustomCommand {
                        existing.name = customName
                        existing.triggers = triggers
                        existing.replacementText = customReplacement
                        customVoiceCommandStore.updateCommand(existing)
                    } else {
                        customVoiceCommandStore.addCommand(CustomVoiceCommand(
                            name: customName,
                            triggers: triggers,
                            replacementText: customReplacement
                        ))
                    }
                    showAddCustom = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(customName.isEmpty || customTriggers.isEmpty || customReplacement.isEmpty)
            }
        }
        .padding()
        .frame(width: 420, height: 340)
    }
}
