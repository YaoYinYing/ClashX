import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("helper_safety_hardening_smoke failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum HelperSafetyHardeningSmokeMain {
    static func main() {
        // Verify structured error classification from helper reply strings.
        require(HelperCommandContract.classifyReplyError(nil) == .unknown,
                "nil reply should classify as unknown")
        require(HelperCommandContract.classifyReplyError("") == .unknown,
                "empty reply should classify as unknown")

        require(HelperCommandContract.classifyReplyError("EINVAL: Invalid HTTP proxy port") == .invalidInput,
                "EINVAL prefix should classify as invalidInput")
        require(HelperCommandContract.classifyReplyError("EINVAL: Invalid SOCKS proxy port") == .invalidInput,
                "EINVAL prefix should classify as invalidInput")
        require(HelperCommandContract.classifyReplyError("EINVAL: Invalid PAC URL") == .invalidInput,
                "EINVAL prefix should classify as invalidInput")
        require(HelperCommandContract.classifyReplyError("EINVAL: Invalid ignore list") == .invalidInput,
                "EINVAL prefix should classify as invalidInput")
        require(HelperCommandContract.classifyReplyError("EINVAL: Invalid restore payload") == .invalidInput,
                "EINVAL with restore payload should classify as invalidInput")

        require(HelperCommandContract.classifyReplyError("EAUTH: Unauthorized client") == .unauthorized,
                "EAUTH prefix should classify as unauthorized")
        require(HelperCommandContract.classifyReplyError("EUNSUPPORTED: Command not available") == .unsupported,
                "EUNSUPPORTED prefix should classify as unsupported")
        require(HelperCommandContract.classifyReplyError("ETIMEOUT: Operation timed out") == .timeout,
                "ETIMEOUT prefix should classify as timeout")
        require(HelperCommandContract.classifyReplyError("EFORBIDDEN: Command not allowed") == .forbidden,
                "EFORBIDDEN prefix should classify as forbidden")
        require(HelperCommandContract.classifyReplyError("ENOTINSTALLED: Helper not found") == .notInstalled,
                "ENOTINSTALLED prefix should classify as notInstalled")

        // Legacy-style error strings (no structured prefix) should be unknown.
        require(HelperCommandContract.classifyReplyError("Invalid proxy port") == .unknown,
                "unprefixed error should classify as unknown")
        require(HelperCommandContract.classifyReplyError("Some random failure message") == .unknown,
                "random message should classify as unknown")

        // Verify all error codes are classifiable.
        require(HelperCommandErrorCode.allCases.contains(.invalidInput),
                "invalidInput must be a valid error code")
        require(HelperCommandErrorCode.allCases.contains(.forbidden),
                "forbidden must be a valid error code")
        require(HelperCommandErrorCode.allCases.contains(.notInstalled),
                "notInstalled must be a valid error code")
        require(HelperCommandErrorCode.allCases.contains(.timeout),
                "timeout must be a valid error code")

        // Verify forbidden command categories are still enforced.
        let forbiddenNotes = HelperCommandRegistry.forbiddenCommandNotes()
        require(forbiddenNotes.contains("arbitrary shell execution"),
                "arbitrary shell execution must stay forbidden")
        require(forbiddenNotes.contains("arbitrary file writes"),
                "arbitrary file writes must stay forbidden")
        require(forbiddenNotes.contains("generic root proxy for app-side logic"),
                "generic root proxy must stay forbidden")
        require(forbiddenNotes.contains("arbitrary route commands"),
                "arbitrary route commands must stay forbidden")
        require(forbiddenNotes.contains("arbitrary process spawning"),
                "arbitrary process spawning must stay forbidden")
        require(forbiddenNotes.contains("arbitrary command strings from the app"),
                "arbitrary command strings from the app must stay forbidden")
        require(forbiddenNotes.contains("arbitrary launchctl calls"),
                "arbitrary launchctl calls must stay forbidden")

        // Verify all reserved TUN commands are still non-executable.
        let reservedTun = HelperCommandRegistry.reservedTunDescriptors()
        require(reservedTun.count == 7,
                "should have 7 reserved TUN commands")
        require(reservedTun.allSatisfy { $0.availability == .reserved },
                "all reserved TUN commands must stay non-executable")
        require(reservedTun.allSatisfy { $0.mutatesSystemState == false },
                "reserved TUN commands must not mutate system state")
        require(reservedTun.allSatisfy(\.requiresPrivilege),
                "reserved TUN commands must require privilege")

        // Verify all implemented system proxy commands are correct.
        let implemented = HelperCommandRegistry.implementedSystemProxyDescriptors()
        require(implemented.count == 5,
                "should have 5 implemented system proxy commands")
        let implementedNames = Set(implemented.map(\.name))
        require(implementedNames.contains(.enableSystemProxy),
                "enableSystemProxy must be implemented")
        require(implementedNames.contains(.disableSystemProxy),
                "disableSystemProxy must be implemented")
        require(implementedNames.contains(.restoreSystemProxy),
                "restoreSystemProxy must be implemented")
        require(implementedNames.contains(.getVersion),
                "getVersion must be implemented")

        print("helper_safety_hardening_smoke passed")
    }
}
