import SwiftUI

struct ShadcnTextFieldModifier: ViewModifier {
    @Environment(\.settingsTheme) private var theme

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, SettingsTheme.spacing12)
            .padding(.vertical, SettingsTheme.spacing8)
            .background(theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.radiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsTheme.radiusMd)
                    .stroke(theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func shadcnTextField() -> some View {
        modifier(ShadcnTextFieldModifier())
    }
}
