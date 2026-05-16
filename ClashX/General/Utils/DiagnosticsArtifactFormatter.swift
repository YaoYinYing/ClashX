//
//  DiagnosticsArtifactFormatter.swift
//  ClashX
//
//  Created by Codex on 2026/5/4.
//

import Foundation

enum DiagnosticsArtifactFormatter {
    static func formatArtifactPreview(title: String, configURL: URL, metadataURL: URL) -> String {
        var lines = [title]
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: configURL.path) else {
            lines.append("Status: missing")
            return lines.joined(separator: "\n")
        }

        lines.append("Path: \(SmartXRedactor.redactPath(configURL.path) ?? configURL.path)")
        if let metadata = ProfileArtifactManager.loadMetadata(at: metadataURL) {
            lines.append("Profile: \(metadata.selectedProfileName) [\(metadata.selectedProfileKind)]")
            lines.append("Source: \(SmartXRedactor.redactPath(metadata.sourceConfigPath) ?? metadata.sourceConfigPath)")
            if let remoteURL = metadata.sourceRemoteURL, !remoteURL.isEmpty {
                lines.append("Remote Source: \(SmartXRedactor.redactURLString(remoteURL) ?? "<redacted-url>")")
            }
            lines.append("Generated: \(DateFormatter.localizedString(from: metadata.generatedAt, dateStyle: .short, timeStyle: .medium))")
            lines.append("Controller Mode: \(metadata.controllerMode)")
            lines.append("Generation Mode: \(metadata.generationMode == "source-copy" ? "Loaded Source Copy" : metadata.generationMode)")
            lines.append("Requested SmartX Overrides: \(metadata.requestedSmartXOverrides ? "yes" : "no")")
            lines.append("Emitted SmartX Overrides: \(metadata.emittedSmartXOverrides ? "yes" : "no")")
            lines.append("Includes Profile Merge: \(metadata.includesProfileMerge ? "yes" : "no")")
            lines.append("Includes Runtime Overrides: \(metadata.includesRuntimeOverrides ? "yes" : "no")")
        } else {
            lines.append("Metadata: unavailable")
        }

        let preview = (try? String(contentsOf: configURL, encoding: .utf8))
            .map { SmartXRedactor.sanitizeText(previewText(from: $0, maxLines: 20)) }
            ?? NSLocalizedString("Config preview could not be read.", comment: "")
        lines.append("Preview:")
        lines.append(preview)
        return lines.joined(separator: "\n")
    }

    static func formatManagedOverrideStatus() -> String {
        let path = Paths.smartXManagedOverrideURL.path
        let redactedPath = SmartXRedactor.redactPath(path) ?? path
        if FileManager.default.fileExists(atPath: path) {
            return "SmartX Managed Override\nStatus: present at \(redactedPath)"
        }
        return "SmartX Managed Override\nStatus: missing"
    }

    private static func previewText(from raw: String, maxLines: Int) -> String {
        let lines = raw.components(separatedBy: .newlines)
        let head = Array(lines.prefix(maxLines))
        var preview = head.joined(separator: "\n")
        if lines.count > maxLines {
            preview.append("\n...")
        }
        return preview.isEmpty ? NSLocalizedString("(empty file)", comment: "") : preview
    }
}
