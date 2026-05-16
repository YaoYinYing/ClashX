import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("helper_command_contract_smoke failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum HelperCommandContractSmokeMain {
    static func main() {
        let implementedSystemProxy = Set(HelperCommandRegistry.implementedSystemProxyDescriptors().map(\.name))
        require(implementedSystemProxy == [
            .getVersion,
            .enableSystemProxy,
            .disableSystemProxy,
            .restoreSystemProxy,
            .readSystemProxy
        ], "implemented system proxy commands drifted")

        let helperDiagnostics = HelperCommandRegistry.helperDiagnosticsDescriptors()
        require(helperDiagnostics.map(\.name) == [.helperStatus], "helper diagnostics commands drifted")

        let reservedTun = HelperCommandRegistry.reservedTunDescriptors()
        require(Set(reservedTun.map(\.name)) == [
            .tunPreflight,
            .tunEnable,
            .tunDisable,
            .tunStatus,
            .tunVerifyRoute,
            .tunVerifyDNS,
            .tunRollback
        ], "reserved TUN command set drifted")
        require(reservedTun.allSatisfy { $0.availability == .reserved }, "reserved TUN command was marked executable")
        require(reservedTun.allSatisfy { $0.category == .tunReserved }, "reserved TUN command category drifted")
        require(reservedTun.allSatisfy { !$0.mutatesSystemState }, "reserved TUN command should not mutate system state in this PR")
        require(reservedTun.allSatisfy { $0.safetyNotes.contains("Reserved only in this PR") }, "reserved TUN commands must stay explicitly non-executable")

        let allDescriptors = HelperCommandRegistry.allDescriptors()
        require(allDescriptors.count == HelperCommandName.allCases.count, "descriptor inventory drifted")
        require(allDescriptors.allSatisfy { !$0.diagnosticDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "empty diagnostic description found")

        let forbiddenNotes = HelperCommandRegistry.forbiddenCommandNotes()
        require(!forbiddenNotes.isEmpty, "forbidden command categories are missing")
        require(forbiddenNotes.contains("arbitrary shell execution"), "arbitrary shell execution must stay forbidden")
        require(forbiddenNotes.contains("generic root proxy for app-side logic"), "generic root proxy must stay forbidden")

        let originalDescriptor = HelperCommandContract.descriptor(for: .helperStatus)
        let encodedDescriptor = try! JSONEncoder().encode(originalDescriptor)
        let decodedDescriptor = try! JSONDecoder().decode(HelperCommandDescriptor.self, from: encodedDescriptor)
        require(decodedDescriptor.name == .helperStatus, "descriptor codable round trip changed name")
        require(decodedDescriptor.category == .helperDiagnostics, "descriptor codable round trip changed category")
        require(decodedDescriptor.availability == .implemented, "descriptor codable round trip changed availability")

        let originalResult = HelperCommandResult(command: .tunStatus,
                                                 success: false,
                                                 errorCode: .unsupported,
                                                 message: "Reserved command is not implemented.",
                                                 recoverySuggestion: "Do not treat reserved TUN commands as executable.")
        let encodedResult = try! JSONEncoder().encode(originalResult)
        let decodedResult = try! JSONDecoder().decode(HelperCommandResult.self, from: encodedResult)
        require(decodedResult.command == .tunStatus, "result codable round trip changed command")
        require(decodedResult.errorCode == .unsupported, "result codable round trip changed error code")
        require(decodedResult.message.contains("not implemented"), "result codable round trip changed message")

        require(HelperCommandContract.isTunCommandReserved(.tunEnable), "tunEnable must stay reserved")
        require(!HelperCommandContract.isTunCommandReserved(.enableSystemProxy), "enableSystemProxy must not be classified as reserved TUN")

        print("helper_command_contract_smoke passed")
    }
}
