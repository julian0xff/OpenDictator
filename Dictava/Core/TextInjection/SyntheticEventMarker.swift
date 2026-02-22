import CoreGraphics

enum SyntheticEventMarker {
    /// Unique identifier to mark events as originating from Dictava
    /// Used to prevent feedback loops when monitoring keyboard events
    static let sourceUserData: Int64 = 0x44494354 // "DICT" in hex

    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == sourceUserData
    }

    static func mark(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: sourceUserData)
    }
}
