@testable import ClashX
import XCTest

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
        XCTAssertEqual(RemoteConfigManager.safeNameFromSuggestedFilename("clean-name.yaml", sourceURL: "https://a.example/config"), "clean-name")
        let fallback = RemoteConfigManager.safeNameFromSuggestedFilename(nil, sourceURL: "https://a.example/config")
        [
            "../../evil.yaml",
            "../evil.yaml",
            "/tmp/evil.yaml",
            "config/evil.yaml",
            "config\\evil.yaml",
            ".hidden.yaml",
            ".yaml",
            "",
            "   ",
            "bad\nname.yaml"
        ].forEach { suggestedFilename in
            XCTAssertEqual(
                RemoteConfigManager.safeNameFromSuggestedFilename(suggestedFilename, sourceURL: "https://a.example/config"),
                fallback,
                "Expected fallback for suggested filename: \(suggestedFilename.debugDescription)"
            )
        }
    }

    func testSuggestedFilenameFallbackIsDeterministicAndDifferentPerURL() {
        let one = RemoteConfigManager.safeNameFromSuggestedFilename(nil, sourceURL: "https://one.example/sub?token=1")
        let two = RemoteConfigManager.safeNameFromSuggestedFilename(nil, sourceURL: "https://two.example/sub?token=2")
        XCTAssertNotEqual(one, two)
        XCTAssertEqual(one, RemoteConfigManager.safeNameFromSuggestedFilename(nil, sourceURL: "https://one.example/sub?token=1"))
        XCTAssertNoThrow(try SafeConfigName(one))
    }

    func testPathContainment() throws {
        let safe = try SafeConfigName("default")
        let base = URL(fileURLWithPath: "/tmp/clash-tests", isDirectory: true)
        let url = try Paths.configFileURL(for: safe, in: base)
        XCTAssertTrue(url.path.hasPrefix(base.standardizedFileURL.path + "/"))
    }

    func testThrowingPathAPIRejectsInvalidNamesWithoutDefaultFallback() {
        XCTAssertThrowsError(try Paths.safeLocalConfigURL(for: "../evil"))
        XCTAssertThrowsError(try Paths.safeConfigFileURL(for: ".hidden", in: URL(fileURLWithPath: "/tmp/clash-tests", isDirectory: true)))
    }

    func testInvalidContentDoesNotChangeExistingConfig() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("clashx-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let target = dir.appendingPathComponent("config.yaml")
        try "initial: true\n".write(to: target, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try RemoteConfigManager.writeConfigAtomically(content: "", targetURL: target))
        let final = try String(contentsOf: target, encoding: .utf8)
        XCTAssertEqual(final, "initial: true\n")
    }
}
