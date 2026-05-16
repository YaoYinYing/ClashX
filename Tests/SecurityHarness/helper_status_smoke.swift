import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("helper_status_smoke failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum HelperStatusSmokeMain {
    static func main() {
        require(HelperTrustState.allCases.map(\.rawValue) == [
            "unknown",
            "unavailable",
            "unsignedDebugBuild",
            "requirementMismatch",
            "notInstalled",
            "installedButUnverified",
            "verified"
        ], "trust state raw values drifted")

        let original = HelperStatus(trustState: .verified,
                                    isPrivilegedHelperAvailable: true,
                                    bundleIdentifier: "com.example.Helper",
                                    launchdLabel: "com.example.Helper",
                                    requirementSummary: "present (42 chars)",
                                    lastCheckedAt: Date(timeIntervalSince1970: 123),
                                    diagnosticMessage: nil,
                                    recoverySuggestion: nil)

        let encoded = try! JSONEncoder().encode(original)
        let decoded = try! JSONDecoder().decode(HelperStatus.self, from: encoded)

        require(decoded.trustState == .verified, "codable round trip changed trust state")
        require(decoded.isPrivilegedHelperAvailable, "codable round trip changed availability")
        require(decoded.bundleIdentifier == "com.example.Helper", "codable round trip changed bundle id")
        require(decoded.launchdLabel == "com.example.Helper", "codable round trip changed launchd label")
        require(decoded.requirementSummary == "present (42 chars)", "codable round trip changed requirement summary")
        require(decoded.diagnosticMessage.contains("runtime verification succeeded"), "verified message should be stable enough for diagnostics")
        require(decoded.recoverySuggestion.contains("does not imply TUN support"), "verified recovery text should stay explicit")

        let debug = HelperStatus(trustState: .unsignedDebugBuild, isPrivilegedHelperAvailable: false)
        require(debug.diagnosticMessage.contains("Debug build"), "unsignedDebugBuild message should mention Debug")

        let mismatch = HelperStatus(trustState: .requirementMismatch, isPrivilegedHelperAvailable: false)
        require(mismatch.diagnosticMessage.contains("missing, empty, or unresolved"), "requirementMismatch message should stay fail-closed")

        print("helper_status_smoke passed")
    }
}
