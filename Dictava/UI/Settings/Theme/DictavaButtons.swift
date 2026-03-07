import SwiftUI

// MARK: - Accent Button (Primary)

struct AccentButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .fontWeight(.medium)
            .foregroundStyle(Color(hex: "#0C0C0C"))
            .padding(.horizontal, DictavaTheme.spacing12)
            .padding(.vertical, DictavaTheme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: DictavaTheme.radiusSm)
                    .fill(isHovered ? theme.accentHover : theme.accent)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Ghost Button

struct EmberGhostButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, DictavaTheme.spacing12)
            .padding(.vertical, DictavaTheme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: DictavaTheme.radiusSm)
                    .fill(isHovered || configuration.isPressed ? theme.surfaceHover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DictavaTheme.radiusSm)
                    .stroke(theme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Destructive Button

struct EmberDestructiveButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(theme.destructive)
            .padding(.horizontal, DictavaTheme.spacing12)
            .padding(.vertical, DictavaTheme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: DictavaTheme.radiusSm)
                    .fill(isHovered || configuration.isPressed ? theme.destructiveDim : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DictavaTheme.radiusSm)
                    .stroke(isHovered || configuration.isPressed ? theme.destructive.opacity(0.3) : theme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Inline Button

struct InlineButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(isHovered ? theme.textPrimary : theme.textSecondary)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Toggle Style

struct DictavaToggleStyle: ToggleStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .foregroundStyle(theme.textPrimary)
            Spacer()
            toggleTrack(isOn: configuration.isOn)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        configuration.isOn.toggle()
                    }
                }
        }
    }

    private func toggleTrack(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? theme.accent : theme.border)
                .frame(width: 36, height: 20)

            Circle()
                .fill(isOn ? Color(hex: "#0C0C0C") : theme.textMuted)
                .frame(width: 16, height: 16)
                .padding(2)
        }
    }
}
