//
//  HelperDiagnosticsProbe.swift
//  ClashX
//
//  Created by Codex on 2026/5/16.
//

import Foundation

enum HelperDiagnosticsProbe {
    private static let requirementInfoKey = "AllowedClientCodeSigningRequirement"
    private static let invalidPlaceholderPatterns = ["$(", "TODO", "REPLACE_ME", "CHANGE_ME", "placeholder"]

    static func currentStatus(bundle: Bundle = .main, fileManager: FileManager = .default) -> HelperStatus {
        let machServiceName = PrivilegedHelperManager.machServiceName
        let bundleHelperURL = bundle.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/\(machServiceName)")
        let installedHelperPath = "/Library/PrivilegedHelperTools/\(machServiceName)"
        let helperInfo = CFBundleCopyInfoDictionaryForURL(bundleHelperURL as CFURL) as? [String: Any]
        let lastCheckedAt = Date()

        guard let helperInfo else {
            return HelperStatus(trustState: .unknown,
                                isPrivilegedHelperAvailable: false,
                                bundleIdentifier: bundle.bundleIdentifier,
                                launchdLabel: machServiceName,
                                requirementSummary: "bundled helper metadata missing",
                                lastCheckedAt: lastCheckedAt)
        }

        let bundleIdentifier = helperInfo["CFBundleIdentifier"] as? String
        let requirement = normalizeRequirement(helperInfo[requirementInfoKey] as? String)
        let requirementSummary = summarizeRequirement(requirement)
        let helperInstalled = fileManager.fileExists(atPath: installedHelperPath)

        if requirementIsPlaceholderLike(requirement) {
            return HelperStatus(trustState: .requirementMismatch,
                                isPrivilegedHelperAvailable: false,
                                bundleIdentifier: bundleIdentifier,
                                launchdLabel: machServiceName,
                                requirementSummary: requirementSummary,
                                lastCheckedAt: lastCheckedAt)
        }

        if let requirement, requirement.isEmpty {
            #if DEBUG
                return HelperStatus(trustState: .unsignedDebugBuild,
                                    isPrivilegedHelperAvailable: helperInstalled,
                                    bundleIdentifier: bundleIdentifier,
                                    launchdLabel: machServiceName,
                                    requirementSummary: requirementSummary,
                                    lastCheckedAt: lastCheckedAt)
            #else
                return HelperStatus(trustState: .requirementMismatch,
                                    isPrivilegedHelperAvailable: false,
                                    bundleIdentifier: bundleIdentifier,
                                    launchdLabel: machServiceName,
                                    requirementSummary: requirementSummary,
                                    lastCheckedAt: lastCheckedAt)
            #endif
        }

        guard helperInstalled else {
            return HelperStatus(trustState: .notInstalled,
                                isPrivilegedHelperAvailable: false,
                                bundleIdentifier: bundleIdentifier,
                                launchdLabel: machServiceName,
                                requirementSummary: requirementSummary,
                                lastCheckedAt: lastCheckedAt)
        }

        return HelperStatus(trustState: .installedButUnverified,
                            isPrivilegedHelperAvailable: true,
                            bundleIdentifier: bundleIdentifier,
                            launchdLabel: machServiceName,
                            requirementSummary: requirementSummary,
                            lastCheckedAt: lastCheckedAt)
    }

    private static func normalizeRequirement(_ requirement: String?) -> String? {
        guard let requirement else {
            return nil
        }
        var normalized = requirement.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("\""), normalized.hasSuffix("\""), normalized.count >= 2 {
            normalized.removeFirst()
            normalized.removeLast()
        }
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func summarizeRequirement(_ requirement: String?) -> String {
        guard let requirement else {
            return "missing"
        }
        if requirement.isEmpty {
            return "empty"
        }
        if requirementIsPlaceholderLike(requirement) {
            return "placeholder-like"
        }
        return "present (\(requirement.count) chars)"
    }

    private static func requirementIsPlaceholderLike(_ requirement: String?) -> Bool {
        guard let requirement, !requirement.isEmpty else {
            return false
        }
        return invalidPlaceholderPatterns.contains(where: { requirement.localizedCaseInsensitiveContains($0) })
    }
}
