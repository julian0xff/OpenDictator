import Foundation

enum WaveformStyle: String, CaseIterable, Identifiable {
    case classicBars  = "classicBars"
    case pulseRing    = "pulseRing"
    case bouncingDots = "bouncingDots"
    case smoothWave   = "smoothWave"
    case glowOrb      = "glowOrb"
    case none         = "none"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classicBars:  return "Classic Bars"
        case .pulseRing:    return "Pulse Ring"
        case .bouncingDots: return "Bouncing Dots"
        case .smoothWave:   return "Smooth Wave"
        case .glowOrb:      return "Glow Orb"
        case .none:         return "None"
        }
    }

    var sfSymbol: String {
        switch self {
        case .classicBars:  return "chart.bar.fill"
        case .pulseRing:    return "circle.dotted"
        case .bouncingDots: return "ellipsis"
        case .smoothWave:   return "waveform.path"
        case .glowOrb:      return "circle.fill"
        case .none:         return "text.alignleft"
        }
    }
}
