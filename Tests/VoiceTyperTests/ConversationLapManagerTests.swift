import XCTest
@testable import VoiceTyper

final class ConversationLapManagerTests: XCTestCase {

    func testInitialLapState() {
        let manager = ConversationLapManager(lapDuration: 600.0, silenceTimeout: 120.0)
        XCTAssertEqual(manager.currentLap, 1)
        XCTAssertFalse(manager.isRunning)

        manager.startSession()
        XCTAssertTrue(manager.isRunning)
        XCTAssertEqual(manager.currentLap, 1)
        XCTAssertNotNil(manager.sessionStartTime)
        XCTAssertNotNil(manager.currentLapStartTime)
    }

    func testLapRolloverAtInterval() {
        let manager = ConversationLapManager(lapDuration: 600.0, silenceTimeout: 120.0)
        manager.startSession()

        var rolloverLap: Int?
        var rolloverFramesCount: Int?

        manager.onLapRollover = { lap, frames in
            rolloverLap = lap
            rolloverFramesCount = frames.count
        }

        // Simulate recording some audio in lap 1
        let dummySamples = [Float](repeating: 0.1, count: 16000)
        manager.appendAudioFrames(dummySamples)

        // Simulate time advancing 10 minutes (601 seconds)
        let startTime = manager.currentLapStartTime ?? Date()
        let futureTime = startTime.addingTimeInterval(601.0)

        let didRoll = manager.evaluateLapRollover(now: futureTime)
        XCTAssertTrue(didRoll, "Lap should roll over when elapsed time exceeds 600s")
        XCTAssertEqual(manager.currentLap, 2, "Current lap should advance to 2")
        XCTAssertEqual(rolloverLap, 1, "Completed lap number reported in callback should be 1")
        XCTAssertEqual(rolloverFramesCount, 16000, "Lap 1 audio frames should be passed to rollover callback")

        // New lap start time should be updated to futureTime
        XCTAssertEqual(manager.currentLapStartTime, futureTime)
    }

    func testSilenceTimeoutDetection() {
        let manager = ConversationLapManager(lapDuration: 600.0, silenceTimeout: 120.0)
        manager.startSession()

        var silenceTriggered = false
        manager.onSilenceTimeout = {
            silenceTriggered = true
        }

        // Below silence threshold (RMS < 0.005) for 60s -> No timeout
        let below60s = manager.evaluateSilence(averageRMS: 0.001, durationInSeconds: 60.0)
        XCTAssertFalse(below60s)
        XCTAssertFalse(silenceTriggered)

        // Below silence threshold for 125s -> Silence timeout triggered!
        let above120s = manager.evaluateSilence(averageRMS: 0.001, durationInSeconds: 125.0)
        XCTAssertTrue(above120s)
        XCTAssertTrue(silenceTriggered, "Silence timeout callback must fire when silence exceeds 120s")
    }

    func testFormattingHelpers() {
        XCTAssertEqual(ConversationLapManager.formatLapNumber(1), "01")
        XCTAssertEqual(ConversationLapManager.formatLapNumber(9), "09")
        XCTAssertEqual(ConversationLapManager.formatLapNumber(12), "12")

        XCTAssertEqual(ConversationLapManager.formatDuration(0), "00:00")
        XCTAssertEqual(ConversationLapManager.formatDuration(65), "01:05")
        XCTAssertEqual(ConversationLapManager.formatDuration(599), "09:59")
        XCTAssertEqual(ConversationLapManager.formatDuration(3665), "61:05")
    }
}
