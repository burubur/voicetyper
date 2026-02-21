import AVFoundation
import Foundation

// MARK: - AudioRecorder

/// Captures microphone audio as 16kHz mono PCM Float arrays,
/// ready for whisper.cpp consumption.
///
/// Uses `AVAudioEngine` with a tap on the input node for real-time
/// buffer capture — no temporary files needed.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var audioFrames: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false

    private let targetSampleRate: Double = 16000.0

    /// Starts capturing audio from the default microphone.
    /// - Throws: If the audio engine fails to start.
    func startRecording() throws {
        guard !isRecording else { return }

        lock.lock()
        audioFrames.removeAll()
        lock.unlock()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Install a tap to capture audio buffers
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, inputSampleRate: inputFormat.sampleRate)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    /// Stops recording and returns the captured audio as 16kHz mono PCM floats.
    /// - Returns: Array of Float samples at 16kHz, suitable for whisper.cpp.
    func stopRecording() -> [Float] {
        guard isRecording else { return [] }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        lock.lock()
        let captured = audioFrames
        audioFrames.removeAll()
        lock.unlock()

        return captured
    }

    // MARK: - Private

    /// Converts an `AVAudioPCMBuffer` to mono 16kHz Float samples.
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, inputSampleRate: Double) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Take the first channel (mono)
        let channelPointer = channelData[0]

        // Resample if input sample rate differs from 16kHz
        let samples: [Float]
        if abs(inputSampleRate - targetSampleRate) < 1.0 {
            // Already at 16kHz — direct copy
            samples = Array(UnsafeBufferPointer(start: channelPointer, count: frameCount))
        } else {
            // Simple linear resampling from inputSampleRate to 16kHz
            let ratio = targetSampleRate / inputSampleRate
            let outputCount = Int(Double(frameCount) * ratio)
            var resampled = [Float](repeating: 0, count: outputCount)
            for i in 0..<outputCount {
                let srcIndex = Double(i) / ratio
                let srcIndexFloor = Int(srcIndex)
                let fraction = Float(srcIndex - Double(srcIndexFloor))
                let idx0 = min(srcIndexFloor, frameCount - 1)
                let idx1 = min(srcIndexFloor + 1, frameCount - 1)
                resampled[i] = channelPointer[idx0] * (1.0 - fraction) + channelPointer[idx1] * fraction
            }
            samples = resampled
        }

        lock.lock()
        audioFrames.append(contentsOf: samples)
        lock.unlock()
    }

    /// Minimum number of audio frames to consider valid speech (~0.3s at 16kHz).
    static let minimumFrameCount = 4800
}
