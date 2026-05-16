//
//  DiagnosticsReportBuilder.swift
//  ClashX
//
//  Created by Codex on 2026/5/2.
//

import Foundation

enum DiagnosticsReportBuilder {
    static func build() -> String {
        let report = [
            headerSection(),
            controllerSection(),
            helperSection(),
            helperCommandContractSection(),
            tunLifecycleBoundarySection(),
            configSection(),
            profileSection(),
            profileArtifactsSection(),
            capabilitySection(),
            providerHealthSection(),
            resourceSection(),
            logSection()
        ].joined(separator: "\n\n")
        return SmartXRedactor.sanitizeText(report)
    }

    private static func headerSection() -> String {
        let lines = [
            "SmartX Diagnostics Report",
            "Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium))",
            "App Version: \(AppVersionUtil.currentVersion) (\(AppVersionUtil.currentBuild))",
            "App Beta: \(AppVersionUtil.isBeta ? "yes" : "no")",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)"
        ]
        return lines.joined(separator: "\n")
    }

    private static func controllerSection() -> String {
        let isEmbedded = Settings.isUsingEmbeddedCore
        var lines = [
            "Controller",
            "----------",
            "Mode: \(isEmbedded ? "embedded" : "external")",
            "Running: \(ConfigManager.shared.isRunning ? "yes" : "no")",
            "URL: \(redactedControllerURL())"
        ]

        if isEmbedded {
            lines.append("Embedded Core Version: \(Settings.embeddedCoreVersion)")
            lines.append("Embedded Core Commit: \(Settings.embeddedCoreCommit)")
            lines.append("Embedded Core Branch: \(Settings.embeddedCoreBranch)")
            lines.append("Embedded Core Build Time: \(Settings.embeddedCoreBuildTime)")
        } else {
            lines.append("Embedded Core Version: not applicable")
        }

        if let snapshot = CapabilityCache.shared.snapshot() {
            lines.append("Capability Snapshot Mode: \(snapshot.mode)")
            lines.append("Capability Snapshot Running: \(snapshot.running ? "yes" : "no")")
            lines.append("Capability Snapshot Identity: \(snapshot.controllerIdentity)")
            lines.append("Capability Snapshot Probed At: \(DateFormatter.localizedString(from: snapshot.probedAt, dateStyle: .short, timeStyle: .medium))")
            lines.append("Capability Snapshot Core Version: \(snapshot.coreVersion ?? "unknown")")
        } else {
            lines.append("Capability Snapshot: unavailable")
        }

        return lines.joined(separator: "\n")
    }

    private static func helperSection() -> String {
        HelperDiagnosticsProbe.currentStatus().renderedSection(title: "Privileged Helper")
    }

    private static func helperCommandContractSection() -> String {
        HelperCommandRegistry.renderedDiagnosticsSection()
    }

    private static func tunLifecycleBoundarySection() -> String {
        let config = ConfigManager.shared.currentConfig
        let helperStatus = HelperDiagnosticsProbe.currentStatus()
        let configPatchAvailability = CapabilityCache.shared.status(for: .configPatch)?.availability ?? .unknown
        let report = TunPreflightPlanner.buildReport(config: config,
                                                     isControllerRunning: ConfigManager.shared.isRunning,
                                                     isUsingEmbeddedCore: Settings.isUsingEmbeddedCore,
                                                     configPatchAvailability: configPatchAvailability,
                                                     helperStatus: helperStatus,
                                                     helperTunDescriptors: HelperCommandRegistry.reservedTunDescriptors())

        var lines = [
            "TUN Lifecycle Boundary",
            "----------------------",
            "Runtime Mode: \(report.runtimeMode.rawValue)",
            "Controller Patch Attemptable: \(report.canAttemptControllerPatch ? "yes" : "no")",
            "Helper Trust State: \(report.helperTrustState.rawValue)",
            "Helper TUN Commands Reserved Only: \(report.helperTunCommandsReserved ? "yes" : "no")",
            "Verification Scope: \(report.verificationScope.rawValue)",
            "Current tun Section: \(config?.tun == nil ? "missing" : "present")",
            "Current tun.enable: \(config?.tun.map { $0.enable ? "true" : "false" } ?? "unknown")"
        ]

        if report.blockers.isEmpty {
            lines.append("Blockers: none")
        } else {
            lines.append("Blockers:")
            lines.append(contentsOf: report.blockers.map { "- \($0.rawValue)" })
        }

        if report.warnings.isEmpty {
            lines.append("Warnings: none")
        } else {
            lines.append("Warnings:")
            lines.append(contentsOf: report.warnings.map { "- \($0)" })
        }

        lines.append("User Message: \(report.userMessage)")
        lines.append("Recovery Suggestion: \(report.recoverySuggestion)")
        lines.append("System-level TUN verification is not implemented.")
        return lines.joined(separator: "\n")
    }

    private static func configSection() -> String {
        var lines = [
            "Config",
            "------",
            "Selected Config: \(ConfigManager.selectConfigName)",
            "Config Home: \(SmartXRedactor.redactPath(Paths.configDirectoryURL.path) ?? Paths.configDirectoryURL.path)",
            "iCloud Config Storage: \(ICloudManager.shared.useiCloud.value ? "enabled" : "disabled")"
        ]

        if let config = ConfigManager.shared.currentConfig {
            lines.append("Current Log Level: \(config.logLevel)")
            lines.append("Current Mode: \(config.mode.rawValue)")
            lines.append("Current TUN Block: \(config.tun == nil ? "not reported" : "present")")
        } else {
            lines.append("Current Config Snapshot: unavailable")
        }

        return lines.joined(separator: "\n")
    }

    private static func profileSection() -> String {
        let currentProfile = ConfigManager.currentProfileDescriptor()
        let sourceSummary = currentProfile.kind == .remote
            ? (SmartXRedactor.redactURLString(currentProfile.sourceSummary) ?? currentProfile.sourceSummary)
            : (SmartXRedactor.redactPath(currentProfile.sourceSummary) ?? currentProfile.sourceSummary)
        var lines = [
            "Profiles",
            "--------",
            "Active Profile Type: \(currentProfile.kind.rawValue)",
            "Active Profile Status: \(currentProfile.statusSummary)",
            "Active Profile Source: \(sourceSummary)",
            "Active Profile Last Update: \(currentProfile.updateSummary)"
        ]

        if let localPath = currentProfile.localURL?.path {
            lines.append("Active Profile Cache Path: \(SmartXRedactor.redactPath(localPath) ?? localPath)")
        } else if ICloudManager.shared.useiCloud.value {
            lines.append("Active Profile Cache Path: managed by iCloud")
        } else {
            lines.append("Active Profile Cache Path: unavailable")
        }

        if let remoteURL = currentProfile.remoteURL {
            lines.append("Active Remote URL: \(SmartXRedactor.redactURLString(remoteURL) ?? "<redacted-url>")")
        }
        if let validationSummary = currentProfile.validationSummary {
            lines.append("Active Profile Validation: \(validationSummary)")
        }
        if let lastFetchSummary = currentProfile.lastFetchSummary {
            lines.append("Active Profile Last Fetch: \(lastFetchSummary)")
        }

        lines.append("Selectable Profiles:")
        if ICloudManager.shared.useiCloud.value {
            lines.append("- inventory omitted in synchronous report while iCloud config storage is enabled")
        } else {
            let selectableProfiles = ConfigManager.getConfigFilesList()
                .sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }
                .map { name in
                    let descriptor = buildProfileDescriptor(named: name)
                    var details = "\(descriptor.menuTitle): \(descriptor.statusSummary)"
                    if let validationSummary = descriptor.validationSummary {
                        details += " | validation=\(validationSummary)"
                    }
                    if let lastFetchSummary = descriptor.lastFetchSummary {
                        details += " | lastFetch=\(lastFetchSummary)"
                    }
                    return "- \(details)"
                }
            lines.append(contentsOf: selectableProfiles.isEmpty ? ["- none"] : selectableProfiles)
        }
        return lines.joined(separator: "\n")
    }

    private static func profileArtifactsSection() -> String {
        let generatedMetadata = ProfileArtifactManager.loadMetadata(at: Paths.successfulReloadMetadataURL)
        let lastKnownGoodMetadata = ProfileArtifactManager.loadMetadata(at: Paths.lastKnownGoodMetadataURL)

        let lines = [
            "Profile Artifacts",
            "-----------------",
            artifactLine(title: "Successful Reload Artifact", path: Paths.successfulReloadArtifactURL.path, metadata: generatedMetadata),
            artifactLine(title: "Last Known Good Config", path: Paths.lastKnownGoodConfigURL.path, metadata: lastKnownGoodMetadata),
            managedOverrideLine(),
            metadataLine(title: "Successful Reload Metadata", path: Paths.successfulReloadMetadataURL.path),
            metadataLine(title: "Last Known Good Metadata", path: Paths.lastKnownGoodMetadataURL.path)
        ]
        return lines.joined(separator: "\n")
    }

    private static func capabilitySection() -> String {
        var lines = [
            "Capabilities",
            "------------"
        ]

        for capability in CoreCapability.allCases {
            let status = CapabilityCache.shared.status(for: capability)
            let availability = status?.availability ?? .unknown
            let message = status?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                lines.append("\(capability.rawValue): \(describe(availability)) (\(message))")
            } else {
                lines.append("\(capability.rawValue): \(describe(availability))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func resourceSection() -> String {
        let lines = [
            "Resources",
            "---------",
            fileStatusLine(title: "Model.bin", path: Paths.smartLightGBMModelPath),
            fileStatusLine(title: "smart_weight_data.csv", path: Paths.smartWeightDataPath),
            fileStatusLine(title: "config.yaml", path: Paths.defaultConfigURL.path)
        ]
        return lines.joined(separator: "\n")
    }

    private static func providerHealthSection() -> String {
        ProviderHealthHistoryManager.summary(limit: 5)
    }

    private static func logSection() -> String {
        let latestLogPath = Logger.shared.logFilePath()
        let lines = [
            "Logs",
            "----",
            "Log Folder: \(SmartXRedactor.redactPath(Logger.shared.logFolder()) ?? Logger.shared.logFolder())",
            "Latest Log File: \(latestLogPath.isEmpty ? "unavailable" : (SmartXRedactor.redactPath(latestLogPath) ?? latestLogPath))"
        ]
        return lines.joined(separator: "\n")
    }

    private static func describe(_ availability: CoreEndpointAvailability) -> String {
        switch availability {
        case .available:
            return "available"
        case .unavailable:
            return "unavailable"
        case .unauthorized:
            return "unauthorized"
        case .unsupported:
            return "unsupported"
        case .unknown:
            return "unknown"
        case .degraded:
            return "degraded"
        }
    }

    private static func redactedControllerURL() -> String {
        guard let components = URLComponents(string: Settings.activeControllerURL) else {
            return "unavailable"
        }

        var host = components.host ?? "unknown"
        if host == "127.0.0.1" || host == "localhost" {
            host = "localhost"
        }

        if let port = components.port, let scheme = components.scheme {
            return "\(scheme)://\(host):\(port)"
        }

        if let scheme = components.scheme {
            return "\(scheme)://\(host)"
        }

        return host
    }

    private static func fileStatusLine(title: String, path: String) -> String {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            return "\(title): missing"
        }

        let attributes = try? fileManager.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber).map {
            ByteCountFormatter.string(fromByteCount: $0.int64Value, countStyle: .file)
        } ?? "unknown size"
        let modified = (attributes?[.modificationDate] as? Date).map {
            DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .medium)
        } ?? "unknown date"
        let redactedPath = SmartXRedactor.redactPath(path) ?? path
        return "\(title): present at \(redactedPath) (\(size), modified \(modified))"
    }

    private static func artifactLine(title: String, path: String, metadata: ProfileArtifactMetadata?) -> String {
        let status = fileStatusLine(title: title, path: path)
        guard let metadata else { return status }
        let sourcePath = SmartXRedactor.redactPath(metadata.sourceConfigPath) ?? metadata.sourceConfigPath
        let remoteURL = SmartXRedactor.redactURLString(metadata.sourceRemoteURL)
        var details = [
            "profile=\(metadata.selectedProfileName)",
            "kind=\(metadata.selectedProfileKind)",
            "source=\(sourcePath)",
            "mode=\(metadata.generationMode == "source-copy" ? "Loaded Source Copy" : metadata.generationMode)",
            "requestedSmartXOverrides=\(metadata.requestedSmartXOverrides ? "yes" : "no")",
            "emittedSmartXOverrides=\(metadata.emittedSmartXOverrides ? "yes" : "no")",
            "profileMerge=\(metadata.includesProfileMerge ? "yes" : "no")",
            "runtimeOverrides=\(metadata.includesRuntimeOverrides ? "yes" : "no")"
        ]
        if let remoteURL, !remoteURL.isEmpty {
            details.append("remote=\(remoteURL)")
        }
        return "\(status) [\(details.joined(separator: ", "))]"
    }

    private static func metadataLine(title: String, path: String) -> String {
        fileStatusLine(title: title, path: path)
    }

    private static func managedOverrideLine() -> String {
        fileStatusLine(title: "SmartX Managed Override", path: Paths.smartXManagedOverrideURL.path)
    }

    private static func buildProfileDescriptor(named name: String) -> ConfigProfileDescriptor {
        let remoteConfig = RemoteConfigManager.shared.configs.first { $0.name == name }
        let safeName = try? SafeConfigName(name)
        let localURL = safeName.flatMap { try? Paths.localConfigURL(for: $0) }
        return ConfigProfileDescriptor(name: name,
                                       kind: remoteConfig == nil ? .local : .remote,
                                       isActive: ConfigManager.selectConfigName == name,
                                       localURL: localURL,
                                       remoteURL: remoteConfig?.url,
                                       lastUpdate: remoteConfig?.updateTime,
                                       fileExists: localURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
                                       validationSummary: remoteConfig?.validationSummary(),
                                       lastFetchSummary: remoteConfig?.updateResultSummary())
    }
}
