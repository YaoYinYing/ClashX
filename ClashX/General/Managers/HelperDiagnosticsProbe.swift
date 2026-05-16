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
            // `bundleIdentifier` must describe the helper bundle when helper
            // metadata is available. Do not substitute the app bundle
            // identifier when helper metadata is missing.
            return HelperStatus(trustState: .unknown,
                                isPrivilegedHelperAvailable: false,
                                bundleIdentifier: nil,
                                launchdLabel: machServiceName,
                                requirementSummary: "bundled helper metadata missing",
                                lastCheckedAt: lastCheckedAt)
        }

        let bundleIdentifier = helperInfo["CFBundleIdentifier"] as? String
        let requirement = normalizeRequirement(helperInfo[requirementInfoKey] as? String)
        let helperInstalled = fileManager.fileExists(atPath: installedHelperPath)

        return HelperStatus.classifyRequirement(requirement,
                                                helperInstalled: helperInstalled,
                                                isDebugBuild: isDebugBuild,
                                                bundleIdentifier: bundleIdentifier,
                                                launchdLabel: machServiceName,
                                                lastCheckedAt: lastCheckedAt,
                                                invalidPlaceholderPatterns: invalidPlaceholderPatterns)
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

    private static var isDebugBuild: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }
}
