import SwiftUI

struct SettingsCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.settingsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacing12) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(theme.textPrimary)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }

            content()
        }
        .padding(SettingsTheme.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.radiusLg))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsTheme.radiusLg)
                .stroke(theme.border, lineWidth: 1)
        )
        .shadow(color: theme.shadow, radius: theme.isDark ? 0 : 3, y: theme.isDark ? 0 : 1)
    }
}
