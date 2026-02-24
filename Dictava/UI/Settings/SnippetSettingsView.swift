import SwiftUI

struct SnippetSettingsView: View {
    @EnvironmentObject var snippetStore: SnippetStore
    @State private var selectedSnippet: Snippet?
    @State private var isEditing = false
    @State private var editTrigger = ""
    @State private var editReplacement = ""

    var body: some View {
        ScrollView {
        Form {
            Section {
                InfoBanner(.tip, "Say a trigger phrase and it will be expanded to the replacement text. Use {{date}}, {{time}}, and {{clipboard}} as template variables.")

                Button {
                    editTrigger = ""
                    editReplacement = ""
                    selectedSnippet = nil
                    isEditing = true
                } label: {
                    Label("Add Snippet", systemImage: "plus")
                }

                if snippetStore.snippets.isEmpty {
                    EmptyStateView(
                        icon: "text.badge.plus",
                        title: "No snippets yet",
                        message: "Add a snippet to quickly expand trigger phrases into longer text."
                    )
                }

                ForEach(snippetStore.snippets) { snippet in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snippet.trigger)
                                .font(.caption.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())

                            Text(snippet.replacement)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button {
                            editTrigger = snippet.trigger
                            editReplacement = snippet.replacement
                            selectedSnippet = snippet
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Edit snippet")

                        Button(role: .destructive) {
                            if let index = snippetStore.snippets.firstIndex(where: { $0.id == snippet.id }) {
                                snippetStore.removeSnippet(at: IndexSet(integer: index))
                            }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.borderless)
                        .help("Delete snippet")
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                SettingsSectionHeader(icon: "text.badge.plus", title: "Snippets", color: .green)
            }
        }
        .formStyle(.grouped)
        }
        .sheet(isPresented: $isEditing) {
            SnippetEditorSheet(
                trigger: $editTrigger,
                replacement: $editReplacement,
                isNew: selectedSnippet == nil
            ) {
                if let existing = selectedSnippet {
                    var updated = existing
                    updated.trigger = editTrigger
                    updated.replacement = editReplacement
                    snippetStore.updateSnippet(updated)
                } else {
                    snippetStore.addSnippet(Snippet(trigger: editTrigger, replacement: editReplacement))
                }
                isEditing = false
            }
        }
    }
}

struct SnippetEditorSheet: View {
    @Binding var trigger: String
    @Binding var replacement: String
    let isNew: Bool
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss

    private let templateVariables = [
        ("{{date}}", "Current date"),
        ("{{time}}", "Current time"),
        ("{{clipboard}}", "Clipboard contents"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text(isNew ? "New Snippet" : "Edit Snippet")
                .font(.headline)

            TextField("Trigger phrase", text: $trigger)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Replacement:")
                    .font(.caption)

                TextEditor(text: $replacement)
                    .font(.body)
                    .frame(minHeight: 100)
                    .border(.quaternary)

                HStack(spacing: 6) {
                    Text("Insert:")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach(templateVariables, id: \.0) { variable in
                        Button {
                            replacement += variable.0
                        } label: {
                            Text(variable.0)
                                .font(.caption2.monospaced())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help(variable.1)
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { onSave() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trigger.isEmpty || replacement.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 320)
    }
}
