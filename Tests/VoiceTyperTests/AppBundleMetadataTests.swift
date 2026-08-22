import XCTest
@testable import VoiceTyper

final class AppBundleMetadataTests: XCTestCase {

    func testUpgradeManagerVersionFormat() {
        let version = UpgradeManager.currentVersion
        XCTAssertFalse(version.hasPrefix("v"), "currentVersion should not contain leading 'v'")
        let parts = version.split(separator: ".")
        XCTAssertEqual(parts.count, 3, "currentVersion should follow semver major.minor.patch format")
        for part in parts {
            XCTAssertNotNil(Int(part), "Each semver component should be numeric")
        }
    }

    func testDetermineAppBundlePath() {
        let appBundlePath = UpgradeManager.determineAppBundlePath()
        XCTAssertTrue(appBundlePath.hasSuffix("VoiceTyper.app"), "App bundle path must end with VoiceTyper.app")
        XCTAssertTrue(appBundlePath.contains("Applications"), "App bundle path must be located in an Applications directory")
    }

    func testDetermineInstallPath() {
        let installPath = UpgradeManager.determineInstallPath()
        XCTAssertTrue(installPath.hasSuffix("voicetyper"), "Install binary path must end with voicetyper")
    }

    func testVoicetyperHomeDirectory() {
        let home = UpgradeManager.voicetyperHome
        XCTAssertTrue(home.path.hasSuffix(".voicetyper"))
        XCTAssertTrue(UpgradeManager.sourceRepoCacheURL.path.hasSuffix(".voicetyper/source_repo"))
    }
}
