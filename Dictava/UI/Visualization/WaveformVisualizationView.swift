import SwiftUI

// MARK: - Dispatcher

struct WaveformVisualizationView: View {
    let style: WaveformStyle
    let level: Float
    let history: [Float]
    let color: Color
    let metrics: IndicatorSizeMetrics

    var body: some View {
        Group {
            switch style {
            case .classicBars:
                ClassicBarsView(levels: history, color: color, maxHeight: metrics.visualizationHeight)
            case .pulseRing:
                PulseRingView(level: level, color: color, size: metrics.visualizationHeight)
            case .bouncingDots:
                BouncingDotsView(level: level, color: color,
                                 width: metrics.visualizationWidth, height: metrics.visualizationHeight)
            case .smoothWave:
                SmoothWaveView(levels: history, color: color,
                               width: metrics.visualizationWidth, height: metrics.visualizationHeight)
            case .glowOrb:
                GlowOrbView(level: level, color: color, size: metrics.visualizationHeight)
            case .none:
                MinimalListeningView(color: color)
            }
        }
        .frame(width: style == .none ? nil : metrics.visualizationWidth,
               height: style == .none ? nil : metrics.visualizationHeight)
    }
}

// MARK: - Classic Bars

struct ClassicBarsView: View {
    let levels: [Float]
    var color: Color = .blue
    var maxHeight: CGFloat = 24

    private let barCount = 20
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = index < levels.count ? CGFloat(levels[index]) : 0
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: barWidth, height: max(2, level * maxHeight))
                    .animation(.interpolatingSpring(stiffness: 300, damping: 15), value: level)
            }
        }
    }
}

// MARK: - Pulse Ring

struct PulseRingView: View {
    let level: Float
    var color: Color = .blue
    let size: CGFloat

    var body: some View {
        let strokeWidth: CGFloat = max(2, size * 0.1)
        let lvl = CGFloat(level)

        ZStack {
            // Outermost faint glow ring
            Circle()
                .stroke(color.opacity(Double(lvl) * 0.15), lineWidth: strokeWidth * 0.4)
                .frame(width: size * 0.95, height: size * 0.95)
                .scaleEffect(0.95 + lvl * 0.25)
                .animation(.interpolatingSpring(stiffness: 80, damping: 8), value: level)

            // Middle breathing ring
            Circle()
                .stroke(color.opacity(0.3 + Double(lvl) * 0.4), lineWidth: strokeWidth * 0.7)
                .frame(width: size * 0.75, height: size * 0.75)
                .scaleEffect(0.9 + lvl * 0.2)
                .animation(.interpolatingSpring(stiffness: 140, damping: 10), value: level)

            // Inner arc — the main visual
            Circle()
                .trim(from: 0.05, to: CGFloat(0.3 + Double(lvl) * 0.65))
                .stroke(color.opacity(0.5 + Double(lvl) * 0.5),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size * 0.55, height: size * 0.55)
                .scaleEffect(0.85 + lvl * 0.3)
                .animation(.interpolatingSpring(stiffness: 200, damping: 12), value: level)

            // Center dot
            Circle()
                .fill(color.opacity(0.6 + Double(lvl) * 0.4))
                .frame(width: size * 0.15, height: size * 0.15)
                .scaleEffect(0.8 + lvl * 0.4)
                .animation(.interpolatingSpring(stiffness: 250, damping: 14), value: level)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Bouncing Dots

struct BouncingDotsView: View {
    let level: Float
    var color: Color = .blue
    let width: CGFloat
    let height: CGFloat

    private let dotCount = 7

    var body: some View {
        let dotDiameter = height * 0.3
        let totalDotsWidth = dotDiameter * CGFloat(dotCount)
        let spacing = max(1, (width - totalDotsWidth) / CGFloat(dotCount - 1))
        let maxBounce = height * 0.5

        HStack(spacing: spacing) {
            ForEach(0..<dotCount, id: \.self) { i in
                let phase = Self.phases[i]
                let intensity = CGFloat(level) * phase.amplitude
                let bounceAmount = intensity * maxBounce
                let dotScale = 1.0 + intensity * 0.3

                Circle()
                    .fill(color.opacity(0.4 + Double(intensity) * 0.6))
                    .frame(width: dotDiameter, height: dotDiameter)
                    .scaleEffect(dotScale)
                    .offset(y: -bounceAmount)
                    .animation(
                        .interpolatingSpring(stiffness: phase.stiffness, damping: phase.damping)
                            .delay(phase.delay),
                        value: level
                    )
            }
        }
        .frame(width: width, height: height, alignment: .bottom)
    }

    private struct DotPhase {
        let amplitude: CGFloat
        let stiffness: Double
        let damping: Double
        let delay: Double
    }

    private static let phases: [DotPhase] = [
        DotPhase(amplitude: 0.5, stiffness: 280, damping: 12, delay: 0.00),
        DotPhase(amplitude: 0.7, stiffness: 260, damping: 11, delay: 0.03),
        DotPhase(amplitude: 0.9, stiffness: 240, damping: 10, delay: 0.06),
        DotPhase(amplitude: 1.0, stiffness: 220, damping: 9,  delay: 0.09),
        DotPhase(amplitude: 0.9, stiffness: 240, damping: 10, delay: 0.06),
        DotPhase(amplitude: 0.7, stiffness: 260, damping: 11, delay: 0.03),
        DotPhase(amplitude: 0.5, stiffness: 280, damping: 12, delay: 0.00),
    ]
}

// MARK: - Smooth Wave

struct SmoothWaveView: View {
    let levels: [Float]
    var color: Color = .blue
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        wavePath(in: CGSize(width: width, height: height))
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .animation(.interpolatingSpring(stiffness: 200, damping: 18), value: levels)
            .frame(width: width, height: height)
    }

    private func wavePath(in size: CGSize) -> Path {
        guard levels.count >= 2 else { return Path() }
        var path = Path()
        let count = levels.count
        let stepX = size.width / CGFloat(count - 1)
        let midY = size.height / 2

        func point(at index: Int) -> CGPoint {
            let x = CGFloat(index) * stepX
            let amplitude = CGFloat(levels[index]) * size.height * 0.45
            let y = midY - (index % 2 == 0 ? amplitude : -amplitude)
            return CGPoint(x: x, y: y)
        }

        path.move(to: point(at: 0))
        for i in 1..<count {
            let prev = point(at: i - 1)
            let curr = point(at: i)
            let control1 = CGPoint(x: (prev.x + curr.x) / 2, y: prev.y)
            let control2 = CGPoint(x: (prev.x + curr.x) / 2, y: curr.y)
            path.addCurve(to: curr, control1: control1, control2: control2)
        }
        return path
    }
}

// MARK: - Glow Orb

struct GlowOrbView: View {
    let level: Float
    var color: Color = .blue
    let size: CGFloat

    var body: some View {
        let baseDiameter = size * 0.55
        let scale = CGFloat(0.8 + Double(level) * 0.5)
        let glowRadius = 2 + CGFloat(level) * 10

        Circle()
            .fill(color.opacity(0.7 + Double(level) * 0.3))
            .frame(width: baseDiameter, height: baseDiameter)
            .scaleEffect(scale)
            .shadow(color: color.opacity(Double(level) * 0.8), radius: glowRadius)
            .animation(.interpolatingSpring(stiffness: 150, damping: 12), value: level)
            .frame(width: size, height: size)
    }
}

// MARK: - Minimal (None)

struct MinimalListeningView: View {
    var color: Color = .blue

    var body: some View {
        Text("Listening...")
            .font(.system(.callout, design: .rounded))
            .foregroundStyle(color.opacity(0.8))
    }
}
