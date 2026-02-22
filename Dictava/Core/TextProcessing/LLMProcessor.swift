import Foundation

/// Stub for Phase 6 - MLX LLM integration for text cleanup
final class LLMProcessor: TextProcessor {
    let name = "LLM Processor"
    var isEnabled = false

    func process(_ text: String) async -> TextProcessingResult {
        // Phase 6: MLX model integration
        // For now, pass through unchanged
        return TextProcessingResult(text: text)
    }
}
