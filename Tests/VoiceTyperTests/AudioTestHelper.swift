import Foundation
@testable import VoiceTyper

/// Helper utilities for creating synthetic audio frames and mock transcribers for testing.
enum AudioTestHelper {
    /// Generates pure silence PCM float frames at 16kHz mono.
    static func generateSilence(durationSeconds: Float = 2.0, sampleRate: Int = 16000) -> [Float] {
        let frameCount = Int(Float(sampleRate) * durationSeconds)
        return [Float](repeating: 0.0, count: frameCount)
    }

    /// Generates a synthetic sine wave tone PCM float frames at 16kHz mono.
    static func generateSineWave(
        frequency: Float = 440.0,
        durationSeconds: Float = 1.0,
        sampleRate: Int = 16000,
        amplitude: Float = 0.5
    ) -> [Float] {
        let frameCount = Int(Float(sampleRate) * durationSeconds)
        return (0..<frameCount).map { index in
            let time = Float(index) / Float(sampleRate)
            return amplitude * sin(2.0 * .pi * frequency * time)
        }
    }
}

/// Mock transcriber that records injected prompts and simulates STT inference.
final class MockTranscriber: Transcriber, @unchecked Sendable {
    var configuredPrompt: String?
    var mockedOutput: String = "Test transcription"
    var lastReceivedAudioFrameCount: Int = 0

    func setInitialPrompt(_ prompt: String?) {
        self.configuredPrompt = prompt
    }

    func transcribe(audioFrames: [Float]) async throws -> String {
        self.lastReceivedAudioFrameCount = audioFrames.count
        
        // If audio is pure silence (RMS < 0.001), simulate whisper silence rejection
        let sumSquares = audioFrames.reduce(0.0) { $0 + ($1 * $1) }
        let rms = sqrt(sumSquares / Float(max(1, audioFrames.count)))
        if rms < 0.001 {
            return ""
        }

        return mockedOutput
    }
}
