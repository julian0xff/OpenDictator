import SwiftUI

struct DictavaCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.theme) private var theme

    var body: some View {
        content()
            .padding(DictavaTheme.spacing16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: DictavaTheme.radiusLg))
            .overlay(
                RoundedRectangle(cornerRadius: DictavaTheme.radiusLg)
                    .stroke(theme.border, lineWidth: 1)
            )
    }
}
