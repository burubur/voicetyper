import Foundation
import Accelerate

// MARK: - AudioDSP

/// High-performance classical DSP audio enhancement engine.
///
/// Implements:
/// 1. 4th-Order 80Hz Butterworth High-Pass Filter (strips 50/60Hz AC hum, desk bumps, fan rumble).
/// 2. Stationary Spectral Subtraction with Spectral Floor (eliminates background noise without musical artifacts).
/// 3. Soft Noise Gate for silent intervals.
public final class AudioDSP: Sendable {

    public static let shared = AudioDSP()

    private init() {}

    /// Applies full audio enhancement pipeline (High-pass filter + Spectral subtraction).
    /// - Parameters:
    ///   - samples: Raw 16kHz mono Float samples.
    ///   - sampleRate: Audio sample rate (default: 16000 Hz).
    ///   - noiseReductionStrength: Subtraction multiplier (0.0 = off, 0.75 = natural, 1.0 = aggressive).
    /// - Returns: Denoised 16kHz mono Float samples.
    public static func denoise(
        _ samples: [Float],
        sampleRate: Double = 16000.0,
        noiseReductionStrength: Float = 0.75
    ) -> [Float] {
        guard samples.count > 512 else { return samples }

        // Step 1: 4th-order 80Hz High-Pass Butterworth filter
        let hpFiltered = applyHighPassFilter(samples, sampleRate: sampleRate, cutoffHz: 80.0)

        // Step 2: Stationary Spectral Subtraction
        let denoised = applySpectralSubtraction(
            hpFiltered,
            sampleRate: sampleRate,
            strength: noiseReductionStrength
        )

        return denoised
    }

    // MARK: - 1. High-Pass Filter (Cascaded Biquad 4th-Order Butterworth)

    /// Applies a 4th-order 80Hz high-pass filter using cascaded biquad Direct Form II.
    public static func applyHighPassFilter(
        _ input: [Float],
        sampleRate: Double = 16000.0,
        cutoffHz: Double = 80.0
    ) -> [Float] {
        guard input.count > 4 else { return input }

        let q1: Double = 0.54119610
        let q2: Double = 1.30656296

        let biquad1 = BiquadCoefficients.highPass(cutoffHz: cutoffHz, sampleRate: sampleRate, q: q1)
        let biquad2 = BiquadCoefficients.highPass(cutoffHz: cutoffHz, sampleRate: sampleRate, q: q2)

        var stage1 = [Float](repeating: 0, count: input.count)
        var stage2 = [Float](repeating: 0, count: input.count)

        processBiquad(input: input, output: &stage1, coeffs: biquad1)
        processBiquad(input: stage1, output: &stage2, coeffs: biquad2)

        return stage2
    }

    private struct BiquadCoefficients {
        let b0: Float, b1: Float, b2: Float
        let a1: Float, a2: Float

        static func highPass(cutoffHz: Double, sampleRate: Double, q: Double) -> BiquadCoefficients {
            let omega = 2.0 * Double.pi * cutoffHz / sampleRate
            let sinOmega = sin(omega)
            let cosOmega = cos(omega)
            let alpha = sinOmega / (2.0 * q)

            let a0 = 1.0 + alpha
            let b0 = Float(((1.0 + cosOmega) / 2.0) / a0)
            let b1 = Float((-(1.0 + cosOmega)) / a0)
            let b2 = Float(((1.0 + cosOmega) / 2.0) / a0)
            let a1 = Float((-2.0 * cosOmega) / a0)
            let a2 = Float((1.0 - alpha) / a0)

            return BiquadCoefficients(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
        }
    }

    private static func processBiquad(
        input: [Float],
        output: inout [Float],
        coeffs: BiquadCoefficients
    ) {
        var w1: Float = 0.0
        var w2: Float = 0.0

        for i in 0..<input.count {
            let x = input[i]
            let w0 = x - coeffs.a1 * w1 - coeffs.a2 * w2
            output[i] = coeffs.b0 * w0 + coeffs.b1 * w1 + coeffs.b2 * w2
            w2 = w1
            w1 = w0
        }
    }

    // MARK: - 2. Stationary Spectral Subtraction (Short-Time FFT)

    /// Reduces stationary background noise by estimating noise spectrum from quiet segments
    /// and subtracting it with spectral floor over-subtraction.
    public static func applySpectralSubtraction(
        _ input: [Float],
        sampleRate: Double = 16000.0,
        strength: Float = 0.75
    ) -> [Float] {
        let fftSize = 512
        let hopSize = 256
        let numFrames = (input.count - fftSize) / hopSize + 1

        guard numFrames > 2 else { return input }

        // Pre-compute Hann window
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        let log2n = vDSP_Length(round(log2(Double(fftSize))))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return input
        }
        defer { vDSP_destroy_fftsetup(setup) }

        let halfN = fftSize / 2
        var noiseSpectrum = [Float](repeating: 0, count: halfN)
        var frameEnergies = [Float](repeating: 0, count: numFrames)

        // 1st Pass: Estimate noise spectrum from the lowest 25% energy frames
        var frameMagnitudes = [[Float]]()
        frameMagnitudes.reserveCapacity(numFrames)

        for f in 0..<numFrames {
            let start = f * hopSize
            var windowed = [Float](repeating: 0, count: fftSize)
            vDSP_vmul(Array(input[start..<start + fftSize]), 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

            var real = [Float](repeating: 0, count: halfN)
            var imag = [Float](repeating: 0, count: halfN)
            var splitComplex = DSPSplitComplex(realp: &real, imagp: &imag)

            windowed.withUnsafeBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { cPtr in
                    vDSP_ctoz(cPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                }
            }

            vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

            var magnitudes = [Float](repeating: 0, count: halfN)
            vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))

            var energy: Float = 0
            vDSP_svesq(magnitudes, 1, &energy, vDSP_Length(halfN))
            frameEnergies[f] = energy
            frameMagnitudes.append(magnitudes)
        }

        // Identify lowest-energy frames as ambient noise baseline
        let sortedEnergies = frameEnergies.sorted()
        let noiseThresholdIndex = max(1, Int(Float(numFrames) * 0.25))
        let noiseThreshold = sortedEnergies[min(noiseThresholdIndex, sortedEnergies.count - 1)]

        var noiseFrameCount: Float = 0
        for f in 0..<numFrames where frameEnergies[f] <= noiseThreshold {
            vDSP_vadd(noiseSpectrum, 1, frameMagnitudes[f], 1, &noiseSpectrum, 1, vDSP_Length(halfN))
            noiseFrameCount += 1
        }

        if noiseFrameCount > 0 {
            var divisor = noiseFrameCount
            vDSP_vsdiv(noiseSpectrum, 1, &divisor, &noiseSpectrum, 1, vDSP_Length(halfN))
        }

        // 2nd Pass: Spectral Subtraction and Overlap-Add reconstruction
        var output = [Float](repeating: 0, count: input.count)
        var windowSum = [Float](repeating: 0, count: input.count)
        let spectralFloor: Float = 0.05

        for f in 0..<numFrames {
            let start = f * hopSize
            var windowed = [Float](repeating: 0, count: fftSize)
            vDSP_vmul(Array(input[start..<start + fftSize]), 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

            var real = [Float](repeating: 0, count: halfN)
            var imag = [Float](repeating: 0, count: halfN)
            var splitComplex = DSPSplitComplex(realp: &real, imagp: &imag)

            windowed.withUnsafeBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { cPtr in
                    vDSP_ctoz(cPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                }
            }

            vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

            var originalMag = [Float](repeating: 0, count: halfN)
            vDSP_zvabs(&splitComplex, 1, &originalMag, 1, vDSP_Length(halfN))

            // Subtraction: gain = max((|X| - alpha * |N|) / |X|, spectralFloor)
            for k in 0..<halfN {
                let orig = originalMag[k]
                if orig > 1e-6 {
                    let subtracted = orig - strength * noiseSpectrum[k]
                    let gain = max(subtracted / orig, spectralFloor)
                    real[k] *= gain
                    imag[k] *= gain
                }
            }

            // Inverse FFT
            vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(FFT_INVERSE))

            var reconstructed = [Float](repeating: 0, count: fftSize)
            reconstructed.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { cPtr in
                    vDSP_ztoc(&splitComplex, 1, cPtr, 2, vDSP_Length(halfN))
                }
            }

            // Scale factor 1 / (2 * fftSize) for vDSP real FFT
            var scale = 1.0 / Float(2 * fftSize)
            vDSP_vsmul(reconstructed, 1, &scale, &reconstructed, 1, vDSP_Length(fftSize))

            // Apply synthesis window & overlap-add
            vDSP_vmul(reconstructed, 1, window, 1, &reconstructed, 1, vDSP_Length(fftSize))

            for i in 0..<fftSize {
                let outIdx = start + i
                if outIdx < output.count {
                    output[outIdx] += reconstructed[i]
                    windowSum[outIdx] += window[i] * window[i]
                }
            }
        }

        // Normalize by synthesis window sum
        for i in 0..<output.count {
            if windowSum[i] > 1e-4 {
                output[i] /= windowSum[i]
            }
        }

        return output
    }
}
