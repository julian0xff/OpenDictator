import SwiftUI

/// Pure black that matches the physical notch — RGB(0,0,0) in device color space.
private let notchBlack = Color(red: 0, green: 0, blue: 0)

struct NotchIndicatorView: View {
    @ObservedObject var session: DictationSession
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var state: NotchIndicatorState
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let hasPhysicalNotch: Bool

    // Spring parameters — open speed configurable, close stays snappy
    private var openAnimation: Animation {
        switch settingsStore.notchAnimationSpeed {
        case .normal: return .spring(response: 0.55, dampingFraction: 0.8)
        case .relaxed: return .spring(response: 0.7, dampingFraction: 0.8)
        }
    }
    private var closeAnimation: Animation {
        .spring(response: 0.45, dampingFraction: 1.0)
    }
    private var currentAnimation: Animation {
        state.isExpanded ? openAnimation : closeAnimation
    }

    private var expansionStyle: NotchExpansionStyle {
        settingsStore.notchExpansionStyle
    }

    // MARK: - Dimensions

    private var currentWidth: CGFloat {
        guard state.isExpanded else { return notchWidth }
        switch expansionStyle {
        case .down: return notchWidth + 30
        case .horizontal: return notchWidth + 160
        case .both: return notchWidth + 120
        }
    }

    private var currentHeight: CGFloat {
        guard state.isExpanded else { return notchHeight }
        switch expansionStyle {
        case .down: return notchHeight + 30
        case .horizontal: return notchHeight
        case .both: return notchHeight + 36
        }
    }

    private var bottomRadius: CGFloat { state.isExpanded ? 20 : 14 }
    private var topRadius: CGFloat { state.isExpanded ? 16 : 6 }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Notch shape — pure black to seamlessly extend the physical notch
            NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                .fill(notchBlack)
                .frame(width: currentWidth, height: currentHeight)

            // Content — only visible when expanded
            if state.isExpanded {
                expandedContent
                    .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(width: currentWidth, height: currentHeight, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(currentAnimation, value: state.isExpanded)
        .animation(currentAnimation, value: session.state)
        .animation(currentAnimation, value: expansionStyle)
    }

    // MARK: - Expanded Content (dispatches by style)

    @ViewBuilder
    private var expandedContent: some View {
        switch expansionStyle {
        case .down:
            downContent
        case .horizontal:
            horizontalContent
        case .both:
            bothContent
        }
    }

    // MARK: - Down Layout

    @ViewBuilder
    private var downContent: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: notchHeight + 2)
            downInnerContent
                .padding(.horizontal, 16)
        }
        .frame(width: currentWidth, height: currentHeight)
    }

    @ViewBuilder
    private var downInnerContent: some View {
        Group {
            switch session.state {
            case .listening:
                WaveformVisualizationView(
                    style: .glowOrb,
                    level: session.audioLevel,
                    history: session.audioLevelHistory,
                    color: settingsStore.notchGlowColor,
                    metrics: notchMetrics
                )
            case .loadingModel:
                statusRow("Loading model...")
            case .transcribing:
                statusRow("Transcribing...")
            case .processing:
                statusRow("Processing...")
            case .injecting:
                statusRow("Typing...")
            case .idle:
                EmptyView()
            }
        }
        .id(session.state)
        .transition(.opacity)
    }

    // MARK: - Horizontal Layout

    @ViewBuilder
    private var horizontalContent: some View {
        HStack(spacing: 0) {
            // Left wing: speech bubble icon
            leftWing
                .frame(width: 80, alignment: .center)

            Spacer()
                .frame(width: notchWidth)

            // Right wing: red dot + elapsed timer
            rightWing
                .frame(width: 80, alignment: .center)
        }
        .frame(width: currentWidth, height: currentHeight)
    }

    @ViewBuilder
    private var leftWing: some View {
        switch session.state {
        case .listening:
            GlowOrbView(level: session.audioLevel, color: settingsStore.notchGlowColor, size: 20)
        case .loadingModel:
            ProgressView()
                .scaleEffect(0.45)
                .frame(width: 14, height: 14)
                .tint(.white)
        case .transcribing, .processing, .injecting:
            ProgressView()
                .scaleEffect(0.45)
                .frame(width: 14, height: 14)
                .tint(.white)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        switch session.state {
        case .listening:
            HStack(spacing: 5) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                Text(formattedElapsed)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white)
            }
        case .loadingModel:
            Text("Loading...")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        case .transcribing:
            Text("Done")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        case .processing:
            Text("Processing")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        case .injecting:
            Text("Typing")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Both Layout

    @ViewBuilder
    private var bothContent: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: notchHeight + 2)
            bothInnerContent
                .padding(.horizontal, 16)
        }
        .frame(width: currentWidth, height: currentHeight)
    }

    @ViewBuilder
    private var bothInnerContent: some View {
        Group {
            switch session.state {
            case .listening:
                WaveformVisualizationView(
                    style: .glowOrb,
                    level: session.audioLevel,
                    history: session.audioLevelHistory,
                    color: settingsStore.notchGlowColor,
                    metrics: notchMetrics
                )
            case .loadingModel:
                statusRow("Loading model...")
            case .transcribing:
                statusRow("Transcribing...")
            case .processing:
                statusRow("Processing...")
            case .injecting:
                statusRow("Typing...")
            case .idle:
                EmptyView()
            }
        }
        .id(session.state)
        .transition(.opacity)
    }

    // MARK: - Helpers

    private func statusRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 14, height: 14)
                .tint(.white)
            Text(text)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var formattedElapsed: String {
        let minutes = session.elapsedSeconds / 60
        let seconds = session.elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Fixed metrics tuned for notch — smaller than floating indicator.
    private var notchMetrics: IndicatorSizeMetrics {
        IndicatorSizeMetrics(
            visualizationWidth: min(notchWidth - 20, 100),
            visualizationHeight: 22
        )
    }
}
