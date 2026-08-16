import Foundation

/// Manages raw audio WAV archiving and transcribed text file storage
/// under `~/.voicetyper/conversation/audio/` and `~/.voicetyper/conversation/text/`.
public final class VoiceConversationStorage: Sendable {

    /// Default base directory: `~/.voicetyper/conversation`
    public static let defaultBaseDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".voicetyper")
        .appendingPathComponent("conversation")

    public let baseDirectory: URL
    public let audioDirectory: URL
    public let textDirectory: URL

    public init(baseDirectory: URL = defaultBaseDirectory) {
        self.baseDirectory = baseDirectory
        self.audioDirectory = baseDirectory.appendingPathComponent("audio")
        self.textDirectory = baseDirectory.appendingPathComponent("text")
    }

    /// Ensures the required storage directories exist on disk.
    public func ensureDirectoriesExist() throws {
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: textDirectory, withIntermediateDirectories: true)
    }

    /// Saves raw PCM float frames as a 16kHz 16-bit mono WAV file and saves transcribed text as a UTF-8 text file.
    /// - Parameters:
    ///   - audioFrames: Array of 16kHz PCM Float samples.
    ///   - transcription: Transcribed text output.
    ///   - sampleRate: Audio sample rate in Hz (default 16000).
    ///   - date: Timestamp of recording.
    ///   - identifier: Optional unique string tag (defaults to 8-char random UUID).
    /// - Returns: Tuple containing the written audio URL and text URL.
    @discardableResult
    public func saveConversation(
        audioFrames: [Float],
        transcription: String,
        sampleRate: Int = 16000,
        date: Date = Date(),
        identifier: String = UUID().uuidString.prefix(8).lowercased()
    ) throws -> (audioURL: URL, textURL: URL) {
        try ensureDirectoriesExist()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: date)

        let filenameBase = "conversation_\(timestamp)_\(identifier)"
        let wavURL = audioDirectory.appendingPathComponent("\(filenameBase).wav")
        let txtURL = textDirectory.appendingPathComponent("\(filenameBase).txt")

        // 1. Generate & write WAV data
        let wavData = Self.createWavData(from: audioFrames, sampleRate: sampleRate)
        try wavData.write(to: wavURL, options: .atomic)

        // 2. Write Transcribed Text (UTF-8)
        let textContent = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        try textContent.write(to: txtURL, atomically: true, encoding: .utf8)

        print("💾 Saved voice memo:")
        print("   🎵 Audio: \(wavURL.path)")
        print("   📝 Text:  \(txtURL.path)")

        return (wavURL, txtURL)
    }

    /// Creates standard 16-bit PCM mono WAV binary data from Float samples.
    public static func createWavData(from samples: [Float], sampleRate: Int = 16000) -> Data {
        var data = Data()

        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate * Int(numChannels) * Int(bitsPerSample / 8))
        let blockAlign = UInt16(numChannels * (bitsPerSample / 8))
        let subchunk2Size = UInt32(samples.count * Int(bitsPerSample / 8))
        let chunkSize = 36 + subchunk2Size

        // RIFF Header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // "fmt " Subchunk
        data.append(contentsOf: "fmt ".utf8)
        let subchunk1Size: UInt32 = 16
        let audioFormat: UInt16 = 1 // PCM
        data.append(contentsOf: withUnsafeBytes(of: subchunk1Size.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        let sampleRateU32 = UInt32(sampleRate)
        data.append(contentsOf: withUnsafeBytes(of: sampleRateU32.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // "data" Subchunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: subchunk2Size.littleEndian) { Array($0) })

        // Write PCM 16-bit signed integer samples (clamped between -1.0 and 1.0)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Sample = Int16(clamped * 32767.0)
            data.append(contentsOf: withUnsafeBytes(of: int16Sample.littleEndian) { Array($0) })
        }

        return data
    }
}
