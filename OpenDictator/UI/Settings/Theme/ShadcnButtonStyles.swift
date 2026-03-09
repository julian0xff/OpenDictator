import SwiftUI

// MARK: - Ghost Button

struct GhostButtonStyle: ButtonStyle {
    @Environment(\.settingsTheme) private var theme
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, SettingsTheme.spacing12)
            .padding(.vertical, SettingsTheme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: SettingsTheme.radiusMd)
                    .fill(isHovered || configuration.isPressed ? theme.controlBackground : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsTheme.radiusMd)
                    .stroke(theme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Destructive Button

struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.settingsTheme) private var theme
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(theme.destructive)
            .padding(.horizontal, SettingsTheme.spacing12)
            .padding(.vertical, SettingsTheme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: SettingsTheme.radiusMd)
                    .fill(isHovered || configuration.isPressed ? theme.destructiveBackground : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsTheme.radiusMd)
                    .stroke(isHovered || configuration.isPressed ? theme.destructive.opacity(0.3) : theme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Primary Button

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.settingsTheme) private var theme
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .fontWeight(.medium)
            .foregroundStyle(Color.white)
            .padding(.horizontal, SettingsTheme.spacing16)
            .padding(.vertical, SettingsTheme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: SettingsTheme.radiusMd)
                    .fill(theme.controlAccent)
            )
            .opacity(isHovered ? 0.9 : (configuration.isPressed ? 0.75 : 1))
            .onHover { isHovered = $0 }
    }
}
