import Foundation

/// Manages raw audio WAV archiving and transcribed text file storage
/// organized by date folders (e.g. `~/.voicetyper/conversation/2026-08-17/audio/` and `text/`).
public final class VoiceConversationStorage: Sendable {

    /// Default base directory: `~/.voicetyper/conversation`
    public static let defaultBaseDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".voicetyper")
        .appendingPathComponent("conversation")

    public let baseDirectory: URL

    public static let dateFolderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    public init(baseDirectory: URL = defaultBaseDirectory) {
        self.baseDirectory = baseDirectory
    }

    /// Returns the day folder URL for a given date (e.g. `.../conversation/2026-08-17/`).
    public func dayDirectory(for date: Date = Date()) -> URL {
        let dateFolder = Self.dateFolderFormatter.string(from: date)
        return baseDirectory.appendingPathComponent(dateFolder)
    }

    /// Returns the audio directory for a given date (e.g. `.../conversation/2026-08-17/audio/`).
    public func audioDirectory(for date: Date = Date()) -> URL {
        return dayDirectory(for: date).appendingPathComponent("audio")
    }

    /// Returns the text directory for a given date (e.g. `.../conversation/2026-08-17/text/`).
    public func textDirectory(for date: Date = Date()) -> URL {
        return dayDirectory(for: date).appendingPathComponent("text")
    }

    /// Ensures the required storage directories exist on disk for the given date.
    public func ensureDirectoriesExist(for date: Date = Date()) throws {
        try FileManager.default.createDirectory(at: audioDirectory(for: date), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: textDirectory(for: date), withIntermediateDirectories: true)
    }

    /// Saves raw PCM float frames as a 16kHz 16-bit mono WAV file and saves transcribed text as a UTF-8 text file,
    /// grouped under a date folder (e.g., `~/.voicetyper/conversation/2026-08-17/`).
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
        identifier: String = UUID().uuidString.prefix(8).lowercased(),
        lap: Int? = nil
    ) throws -> (audioURL: URL, textURL: URL) {
        try ensureDirectoriesExist(for: date)

        let timestamp = Self.timestampFormatter.string(from: date)
        let lapSuffix = (lap != nil) ? "_part\(lap!)" : ""
        let filenameBase = "conversation_\(timestamp)_\(identifier)\(lapSuffix)"

        let wavURL = audioDirectory(for: date).appendingPathComponent("\(filenameBase).wav")
        let txtURL = textDirectory(for: date).appendingPathComponent("\(filenameBase).txt")

        // 1. Generate & write WAV data
        let wavData = Self.createWavData(from: audioFrames, sampleRate: sampleRate)
        try wavData.write(to: wavURL, options: .atomic)

        // 2. Write transcription text file
        let header = "--- Conversation Memory \(lap != nil ? "(Part \(lap!))" : "") ---\nDate: \(date)\nSamples: \(audioFrames.count)\n\n"
        let fullText = header + transcription
        try fullText.write(to: txtURL, atomically: true, encoding: .utf8)

        print("💾 Saved voice memo:")
        print("   📁 Date:  \(Self.dateFolderFormatter.string(from: date))")
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
