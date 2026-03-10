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
                .frame(width: 40, height: 22)

            Circle()
                .fill(Color.white)
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                .padding(2)
        }
    }
}
