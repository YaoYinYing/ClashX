import XCTest
@testable import ClashX

final class PathSafetyTests: XCTestCase {
    func testValidConfigNames() throws {
        ["default", "My Config", "proxy-us-1", "test.profile"].forEach {
            XCTAssertNoThrow(try SafeConfigName($0))
        }
    }

    func testInvalidConfigNames() {
        let cases = [
            "../evil", "../../Library/LaunchAgents/pwn", "/tmp/test", "config/evil", "config\\evil",
            ".hidden", ".", "..", "", "   ", "a\nname"
        ]
        for item in cases {
            XCTAssertThrowsError(try SafeConfigName(item), "Expected invalid: \(item)")
        }
    }

    func testSuggestedFilenameFallback() {
        XCTAssertEqual(RemoteConfigManager.safeNameFromSuggestedFilename("clean-name.yaml"), "clean-name")
        XCTAssertEqual(RemoteConfigManager.safeNameFromSuggestedFilename("../../evil.yaml"), "remote-config")
        XCTAssertEqual(RemoteConfigManager.safeNameFromSuggestedFilename(".hidden.yaml"), "remote-config")
    }

    func testPathContainment() throws {
        let safe = try SafeConfigName("default")
        let base = URL(fileURLWithPath: "/tmp/clash-tests", isDirectory: true)
        let url = try Paths.configFileURL(for: safe, in: base)
        XCTAssertTrue(url.path.hasPrefix(base.standardizedFileURL.path + "/"))
    }
}
