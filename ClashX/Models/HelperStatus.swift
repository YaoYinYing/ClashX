//
//  HelperStatus.swift
//  ClashX
//
//  Created by Codex on 2026/5/16.
//

import Foundation

enum HelperTrustState: String, Codable, CaseIterable {
    case unknown
    case unavailable
    case unsignedDebugBuild
    case requirementMismatch
    case notInstalled
    case installedButUnverified
    case verified
}

struct HelperStatus: Codable {
    var trustState: HelperTrustState
    var isPrivilegedHelperAvailable: Bool
    var bundleIdentifier: String?
    var launchdLabel: String?
    var requirementSummary: String?
    var lastCheckedAt: Date?
    var diagnosticMessage: String
    var recoverySuggestion: String

    init(trustState: HelperTrustState,
         isPrivilegedHelperAvailable: Bool,
         bundleIdentifier: String? = nil,
         launchdLabel: String? = nil,
         requirementSummary: String? = nil,
         lastCheckedAt: Date? = nil,
         diagnosticMessage: String? = nil,
         recoverySuggestion: String? = nil) {
        self.trustState = trustState
        self.isPrivilegedHelperAvailable = isPrivilegedHelperAvailable
        self.bundleIdentifier = bundleIdentifier
        self.launchdLabel = launchdLabel
        self.requirementSummary = requirementSummary
        self.lastCheckedAt = lastCheckedAt
        self.diagnosticMessage = diagnosticMessage ?? Self.defaultDiagnosticMessage(for: trustState,
                                                                                    requirementSummary: requirementSummary)
        self.recoverySuggestion = recoverySuggestion ?? Self.defaultRecoverySuggestion(for: trustState)
    }

    var availabilitySummary: String {
        isPrivilegedHelperAvailable ? "available" : "unavailable"
    }

    // Missing requirement metadata is a helper trust failure, not a helper
    // installation-state signal. Install/update flows should fail closed before
    // proceeding when the requirement is missing, placeholder-like, or invalid.
    static func classifyRequirement(_ requirement: String?,
                                    helperInstalled: Bool,
                                    isDebugBuild: Bool,
                                    bundleIdentifier: String?,
                                    launchdLabel: String?,
                                    lastCheckedAt: Date?,
                                    invalidPlaceholderPatterns: [String]) -> HelperStatus
    {
        let summary = summarizeRequirement(requirement, invalidPlaceholderPatterns: invalidPlaceholderPatterns)

        if requirement == nil || summary == "placeholder-like" {
            return HelperStatus(trustState: .requirementMismatch,
                                isPrivilegedHelperAvailable: false,
                                bundleIdentifier: bundleIdentifier,
                                launchdLabel: launchdLabel,
                                requirementSummary: summary,
                                lastCheckedAt: lastCheckedAt)
        }

        if let requirement, requirement.isEmpty {
            if isDebugBuild {
                return HelperStatus(trustState: .unsignedDebugBuild,
                                    isPrivilegedHelperAvailable: helperInstalled,
                                    bundleIdentifier: bundleIdentifier,
                                    launchdLabel: launchdLabel,
                                    requirementSummary: summary,
                                    lastCheckedAt: lastCheckedAt)
            }
            return HelperStatus(trustState: .requirementMismatch,
                                isPrivilegedHelperAvailable: false,
                                bundleIdentifier: bundleIdentifier,
                                launchdLabel: launchdLabel,
                                requirementSummary: summary,
                                lastCheckedAt: lastCheckedAt)
        }

        if helperInstalled {
            return HelperStatus(trustState: .installedButUnverified,
                                isPrivilegedHelperAvailable: true,
                                bundleIdentifier: bundleIdentifier,
                                launchdLabel: launchdLabel,
                                requirementSummary: summary,
                                lastCheckedAt: lastCheckedAt)
        }

        return HelperStatus(trustState: .notInstalled,
                            isPrivilegedHelperAvailable: false,
                            bundleIdentifier: bundleIdentifier,
                            launchdLabel: launchdLabel,
                            requirementSummary: summary,
                            lastCheckedAt: lastCheckedAt)
    }

    func renderedSection(title: String) -> String {
        [
            title,
            String(repeating: "-", count: title.count),
            "Trust State: \(trustState.rawValue)",
            "Availability: \(availabilitySummary)",
            "Bundle Identifier: \(bundleIdentifier ?? "unknown")",
            "Launchd Label: \(launchdLabel ?? "unknown")",
            "Requirement Summary: \(requirementSummary ?? "unknown")",
            "Last Checked: \(formatted(lastCheckedAt))",
            "Diagnostic Message: \(diagnosticMessage)",
            "Recovery Suggestion: \(recoverySuggestion)"
        ].joined(separator: "\n")
    }

    private static func defaultDiagnosticMessage(for trustState: HelperTrustState,
                                                 requirementSummary: String?) -> String {
        switch trustState {
        case .unknown:
            return "SmartX could not determine a reliable helper status from the current app bundle."
        case .unavailable:
            return "SmartX could not inspect the helper boundary from this runtime context."
        case .unsignedDebugBuild:
            return "This Debug build uses an empty helper client requirement, so helper trust stays diagnostic-only and may fail closed during real installation."
        case .requirementMismatch:
            return "The bundled helper requirement metadata is missing, empty, or unresolved, so SmartX treats the helper trust boundary as mismatched."
        case .notInstalled:
            return "Bundled helper metadata looks present, but no installed privileged helper binary was found."
        case .installedButUnverified:
            return "An installed privileged helper file exists, but this read-only probe did not perform a runtime XPC or blessing verification."
        case .verified:
            if let requirementSummary, !requirementSummary.isEmpty {
                return "Helper metadata and runtime verification succeeded with requirement summary: \(requirementSummary)."
            }
            return "Helper metadata and runtime verification succeeded."
        }
    }

    private static func defaultRecoverySuggestion(for trustState: HelperTrustState) -> String {
        switch trustState {
        case .unknown, .unavailable:
            return "Use this status only as a diagnostic boundary. Real helper installation and signing validation remain separate checks."
        case .unsignedDebugBuild:
            return "Do not treat Debug helper status as production-ready. Use Release helper requirement checks for fail-closed verification."
        case .requirementMismatch:
            return "Fix SMARTX_ALLOWED_CLIENT_REQUIREMENT and bundled helper metadata before trusting helper installation behavior."
        case .notInstalled:
            return "Helper installation may still be required for system proxy management, but it does not provide helper-backed TUN support."
        case .installedButUnverified:
            return "Treat the helper as system-proxy-only until a separate audited helper command contract and runtime verification path exist."
        case .verified:
            return "Verified helper trust does not imply TUN support. Future helper-backed TUN still requires a separate command contract."
        }
    }

    private static func summarizeRequirement(_ requirement: String?,
                                             invalidPlaceholderPatterns: [String]) -> String {
        guard let requirement else {
            return "missing"
        }
        if requirement.isEmpty {
            return "empty"
        }
        if invalidPlaceholderPatterns.contains(where: { requirement.localizedCaseInsensitiveContains($0) }) {
            return "placeholder-like"
        }
        return "present (\(requirement.count) chars)"
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else {
            return "unknown"
        }
        return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .medium)
    }
}
