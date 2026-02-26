import SwiftUI

// MARK: - Section Header

struct SettingsSectionHeader: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var color: Color = .blue
    @Environment(\.settingsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }
}

// MARK: - Info Banner

enum InfoBannerStyle {
    case info, tip, warning

    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .tip: return "lightbulb.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}

struct InfoBanner: View {
    let style: InfoBannerStyle
    let text: String
    @Environment(\.settingsTheme) private var theme

    init(_ style: InfoBannerStyle, _ text: String) {
        self.style = style
        self.text = text
    }

    private var accentColor: Color {
        switch style {
        case .info: return theme.textSecondary
        case .tip: return theme.controlAccent
        case .warning: return theme.warning
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 2)

            Image(systemName: style.icon)
                .foregroundStyle(accentColor)
                .font(.caption)

            Text(text)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.vertical, 10)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsTheme.radiusMd)
                .stroke(theme.border, lineWidth: 1)
        )
    }
}

// MARK: - Styled Stat Card

struct StyledStatCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    var color: Color = .blue
    @Environment(\.settingsTheme) private var theme

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(theme.textTertiary)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(theme.textSecondary)
            }
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.radiusLg))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsTheme.radiusLg)
                .stroke(theme.border, lineWidth: 1)
        )
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    @Environment(\.settingsTheme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(theme.textTertiary)
            Text(title)
                .foregroundStyle(theme.textSecondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
