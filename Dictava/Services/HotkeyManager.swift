import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleDictation = Self("toggleDictation", default: .init(.space, modifiers: .option))
    static let copyLastTranscription = Self("copyLastTranscription", default: .init(.space, modifiers: [.option, .shift]))
}
