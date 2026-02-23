import Foundation

/// Thread-safe buffer for collecting audio samples from the audio callback.
/// Used by ASR providers to accumulate samples between transcription calls.
actor AudioSampleBuffer {
    private var samples: [Float] = []

    func append(_ newSamples: [Float]) {
        samples.append(contentsOf: newSamples)
    }

    func getAll() -> [Float] {
        samples
    }

    func clear() {
        samples.removeAll()
    }

    /// Serialization barrier — by the time this returns, all previously-enqueued
    /// append() calls have completed (actor serial execution guarantee).
    func flush() {
        // no-op: the actor's serial executor ensures ordering
    }
}
