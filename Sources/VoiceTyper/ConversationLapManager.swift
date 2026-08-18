import Foundation

/// Manages long-form conversation sessions with rolling lap segmentation (e.g. 10-minute chapters)
/// and automatic idle silence detection to protect memory and storage.
public final class ConversationLapManager: @unchecked Sendable {

    /// Duration limit per lap before rolling over to the next segment (default: 10 minutes = 600s).
    public var lapDurationLimit: TimeInterval

    /// Duration of continuous silence before auto-stopping (default: 2 minutes = 120s).
    public var silenceTimeoutLimit: TimeInterval

    public private(set) var currentLap: Int = 1
    public private(set) var sessionStartTime: Date?
    public private(set) var currentLapStartTime: Date?
    public private(set) var isRunning: Bool = false

    private var currentLapFrames: [Float] = []
    private let lock = NSLock()

    /// Invoked when a lap completes and rolls over to the next (completedLapNumber, lapAudioFrames).
    public var onLapRollover: ((Int, [Float]) -> Void)?

    /// Invoked when continuous silence exceeds `silenceTimeoutLimit`.
    public var onSilenceTimeout: (() -> Void)?

    public init(lapDuration: TimeInterval = 600.0, silenceTimeout: TimeInterval = 120.0) {
        self.lapDurationLimit = lapDuration
        self.silenceTimeoutLimit = silenceTimeout
    }

    /// Starts a new conversation capture session.
    public func startSession(now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }

        self.currentLap = 1
        self.sessionStartTime = now
        self.currentLapStartTime = now
        self.isRunning = true
        self.currentLapFrames.removeAll()
    }

    /// Stops the session and returns the final lap index and total session duration.
    public func stopSession(now: Date = Date()) -> (lap: Int, totalDuration: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }

        let totalDuration = now.timeIntervalSince(sessionStartTime ?? now)
        let finalLap = currentLap
        self.isRunning = false
        self.currentLapFrames.removeAll()
        return (lap: finalLap, totalDuration: totalDuration)
    }

    /// Appends audio samples to the active lap buffer.
    public func appendAudioFrames(_ frames: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }
        currentLapFrames.append(contentsOf: frames)
    }

    /// Flushes and returns the current lap audio frames.
    public func flushCurrentLapFrames() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let frames = currentLapFrames
        currentLapFrames.removeAll()
        return frames
    }

    /// Checks if the current lap has exceeded the duration limit and rolls over if needed.
    /// - Returns: `true` if a lap rollover occurred.
    @discardableResult
    public func evaluateLapRollover(now: Date = Date()) -> Bool {
        lock.lock()
        guard isRunning, let lapStart = currentLapStartTime else {
            lock.unlock()
            return false
        }

        let elapsed = now.timeIntervalSince(lapStart)
        guard elapsed >= lapDurationLimit else {
            lock.unlock()
            return false
        }

        let completedLap = currentLap
        let lapFrames = currentLapFrames
        currentLapFrames.removeAll()

        currentLap += 1
        currentLapStartTime = now
        lock.unlock()

        onLapRollover?(completedLap, lapFrames)
        return true
    }

    /// Evaluates ambient silence against threshold and timeout.
    /// - Returns: `true` if silence timeout was triggered.
    @discardableResult
    public func evaluateSilence(averageRMS: Float, durationInSeconds: TimeInterval, thresholdRMS: Float = 0.005) -> Bool {
        guard isRunning else { return false }

        if averageRMS < thresholdRMS && durationInSeconds >= silenceTimeoutLimit {
            onSilenceTimeout?()
            return true
        }
        return false
    }

    // MARK: - Formatting Helpers

    /// Formats lap number as a 2-digit string (e.g. `01`, `02`).
    public static func formatLapNumber(_ lap: Int) -> String {
        return String(format: "%02d", max(1, lap))
    }

    /// Formats duration in seconds to `MM:SS`.
    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds))
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
