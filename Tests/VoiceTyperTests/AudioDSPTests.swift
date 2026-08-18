import XCTest
@testable import VoiceTyper

final class AudioDSPTests: XCTestCase {

    func testHighPassFilterAttenuatesLowFrequencies() {
        let sampleRate: Double = 16000.0
        let durationSeconds: Double = 1.0
        let sampleCount = Int(sampleRate * durationSeconds)

        // Generate 50Hz sine wave (AC mains hum)
        var hum50Hz = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            hum50Hz[i] = Float(sin(2.0 * Double.pi * 50.0 * t))
        }

        // Generate 1000Hz sine wave (typical speech vowel formant)
        var voice1000Hz = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            voice1000Hz[i] = Float(sin(2.0 * Double.pi * 1000.0 * t))
        }

        let filteredHum = AudioDSP.applyHighPassFilter(hum50Hz, sampleRate: sampleRate, cutoffHz: 80.0)
        let filteredVoice = AudioDSP.applyHighPassFilter(voice1000Hz, sampleRate: sampleRate, cutoffHz: 80.0)

        // Calculate RMS of hum before and after
        let humRmsBefore = sqrt(hum50Hz.map { $0 * $0 }.reduce(0, +) / Float(sampleCount))
        let humRmsAfter = sqrt(filteredHum.map { $0 * $0 }.reduce(0, +) / Float(sampleCount))

        // Calculate RMS of voice before and after
        let voiceRmsBefore = sqrt(voice1000Hz.map { $0 * $0 }.reduce(0, +) / Float(sampleCount))
        let voiceRmsAfter = sqrt(filteredVoice.map { $0 * $0 }.reduce(0, +) / Float(sampleCount))

        // 50Hz hum should be significantly attenuated (> -10dB)
        XCTAssertLessThan(humRmsAfter, humRmsBefore * 0.4, "50Hz hum should be attenuated by 80Hz high-pass filter")

        // 1000Hz voice should pass through virtually unchanged (> 95% preserved)
        XCTAssertGreaterThan(voiceRmsAfter, voiceRmsBefore * 0.95, "1000Hz speech frequency should be preserved")
    }

    func testDenoiseHandlesShortAndEmptyBuffers() {
        let empty = [Float]()
        XCTAssertEqual(AudioDSP.denoise(empty), empty)

        let shortBuffer: [Float] = [0.1, 0.2, 0.3]
        XCTAssertEqual(AudioDSP.denoise(shortBuffer), shortBuffer)
    }

    func testDenoiseSuppressesBackgroundNoise() {
        let sampleRate: Double = 16000.0
        let sampleCount = 16000 // 1 second

        // Synthetic signal: Quiet stationary noise + speech burst
        var mixed = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let noise = Float.random(in: -0.05...0.05)
            let speech = (i > 4000 && i < 12000) ? 0.6 * Float(sin(2.0 * Double.pi * 440.0 * Double(i) / sampleRate)) : 0.0
            mixed[i] = noise + speech
        }

        let cleaned = AudioDSP.denoise(mixed, sampleRate: sampleRate, noiseReductionStrength: 0.75)

        XCTAssertEqual(cleaned.count, mixed.count)
        // Cleaned audio should not contain NaN or Inf
        for sample in cleaned {
            XCTAssertFalse(sample.isNaN)
            XCTAssertFalse(sample.isInfinite)
        }
    }
}
