import AppKit
import SwiftUI
import Combine

@MainActor
final class DictationIndicatorWindow {
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()

    init(dictationSession: DictationSession) {
        dictationSession.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if state.isActive {
                    self?.show(session: dictationSession)
                } else {
                    self?.hide()
                }
            }
            .store(in: &cancellables)
    }

    private func show(session: DictationSession) {
        if panel == nil {
            let contentView = DictationIndicatorView(session: session)
            let hostingView = NSHostingView(rootView: contentView)
            hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 48)

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 48),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
            panel.contentView = hostingView
            panel.isMovableByWindowBackground = true
            panel.hasShadow = false

            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - 160
                let y = screenFrame.maxY - 70
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }

            self.panel = panel
        }

        panel?.alphaValue = 0
        panel?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.panel?.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}

// MARK: - Indicator View

struct DictationIndicatorView: View {
    @ObservedObject var session: DictationSession

    var body: some View {
        HStack(spacing: 10) {
            stateIcon
            centerContent
            if session.state == .listening {
                AudioWaveformView(levels: session.audioLevelHistory)
                    .frame(width: 80, height: 20)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .animation(.easeInOut(duration: 0.2), value: session.state)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch session.state {
        case .listening:
            PulsingRecordDot()
        case .transcribing, .processing:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
        case .injecting:
            Image(systemName: "keyboard.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .executingCommand:
            Image(systemName: "command")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        switch session.state {
        case .listening:
            EmptyView()
        case .transcribing:
            Text("Transcribing...")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.secondary)
        case .processing:
            Text("Processing...")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.secondary)
        case .injecting:
            Text("Typing...")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.secondary)
        case .executingCommand:
            Text("Executing...")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }
}

// MARK: - Pulsing Record Dot

struct PulsingRecordDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(.red.opacity(0.4), lineWidth: 2)
                    .scaleEffect(isPulsing ? 1.8 : 1.0)
                    .opacity(isPulsing ? 0 : 0.6)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Audio Waveform View

struct AudioWaveformView: View {
    let levels: [Float]

    private let barCount = 20
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = index < levels.count ? CGFloat(levels[index]) : 0
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor(for: levels.indices.contains(index) ? levels[index] : 0))
                    .frame(width: barWidth, height: max(2, level * 24))
                    .animation(.interpolatingSpring(stiffness: 300, damping: 15), value: level)
            }
        }
    }

    private func barColor(for level: Float) -> Color {
        if level > 0.8 { return .red }
        if level > 0.5 { return .orange }
        return .blue
    }
}
