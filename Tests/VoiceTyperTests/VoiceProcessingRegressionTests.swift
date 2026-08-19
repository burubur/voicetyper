import XCTest
import AVFoundation
@testable import VoiceTyper

final class VoiceProcessingRegressionTests: XCTestCase {

    /// Ensures AudioRecorder never enables Voice Processing (AUVoiceIO) in idle or recording modes.
    /// This guarantees CoreAudio will not duck background audio (Apple Music, Spotify) or degrade
    /// Bluetooth headphones to low-bandwidth HFP telephony mode.
    func testAudioRecorderNeverEnablesVoiceProcessing() throws {
        guard #available(macOS 13.0, *) else {
            throw XCTSkip("Voice Processing API requires macOS 13.0 or later")
        }

        let recorder = AudioRecorder()

        // 1. Idle state on initialization
        XCTAssertFalse(
            recorder.isVoiceProcessingEnabled,
            "AudioRecorder should not have voice processing enabled when idle."
        )

        // 2. Recording state
        do {
            try recorder.startRecording()
            XCTAssertTrue(recorder.isRecording)
            XCTAssertFalse(
                recorder.isVoiceProcessingEnabled,
                "AudioRecorder must NOT enable voice processing while recording to prevent system-wide audio ducking."
            )
        } catch {
            // If running in an environment without microphone access, proceed to check teardown
        }

        // 3. Stopped / idle state
        _ = recorder.stopRecording()
        XCTAssertFalse(recorder.isRecording)
        XCTAssertFalse(
            recorder.isVoiceProcessingEnabled,
            "AudioRecorder must remain false in idle state after recording stops."
        )
    }
}
