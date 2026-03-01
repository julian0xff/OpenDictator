import Foundation

/// Thread-safe buffer for collecting audio samples from the audio callback.
/// Used by ASR providers to accumulate samples between transcription calls.
actor AudioSampleBuffer {
    private var samples: [Float] = []
    private let maxSamples: Int?

    init(maxSamples: Int? = nil) {
        self.maxSamples = maxSamples
    }

    func append(_ newSamples: [Float]) {
        guard !newSamples.isEmpty else { return }
        samples.append(contentsOf: newSamples)
        if let maxSamples, samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    func getAll() -> [Float] {
        samples
    }

    func count() -> Int {
        samples.count
    }

    /// Atomically returns all buffered samples and clears the buffer.
    /// Samples appended after this call begins will remain for the next read.
    func drainAll() -> [Float] {
        let drained = samples
        samples.removeAll(keepingCapacity: true)
        return drained
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
