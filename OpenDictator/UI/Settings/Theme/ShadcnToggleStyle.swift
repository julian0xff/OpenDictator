import SwiftUI

struct ShadcnToggleStyle: ToggleStyle {
    @Environment(\.settingsTheme) private var theme

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
                .fill(isOn ? theme.controlAccent : theme.controlBackground)
                .frame(width: 36, height: 20)

            Circle()
                .fill(isOn ? Color.white : theme.textSecondary)
                .frame(width: 16, height: 16)
                .padding(2)
        }
    }
}
