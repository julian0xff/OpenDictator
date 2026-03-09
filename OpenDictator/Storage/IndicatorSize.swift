import CoreGraphics

struct IndicatorSizeMetrics {
    let visualizationWidth: CGFloat
    let visualizationHeight: CGFloat

    /// Scale ranges from 0.0 (smallest) to 1.0 (largest).
    /// At 0.5, dimensions match the original default (80 x 24).
    static func metrics(forScale scale: Double) -> IndicatorSizeMetrics {
        let clamped = min(1.0, max(0.0, scale))
        // Width:  40 (scale 0) → 80 (scale 0.5) → 140 (scale 1.0)
        // Height: 12 (scale 0) → 24 (scale 0.5) → 42  (scale 1.0)
        let width  = 40.0 + clamped * 100.0
        let height = 12.0 + clamped * 30.0
        return IndicatorSizeMetrics(
            visualizationWidth: CGFloat(width),
            visualizationHeight: CGFloat(height)
        )
    }
}
