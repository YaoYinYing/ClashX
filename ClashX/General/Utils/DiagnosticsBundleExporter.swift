//
//  DiagnosticsBundleExporter.swift
//  ClashX
//
//  Created by Codex on 2026/5/3.
//

import Foundation

struct DiagnosticsBundleManifest: Codable {
    let generatedAt: Date
    let appVersion: String
    let appBuild: String
    let controllerMode: String
    let activeProfileName: String
    let activeProfileType: String
    let logFileName: String?
}

enum DiagnosticsBundleExporter {
    enum ExportError: LocalizedError {
        case bundleAlreadyExists(String)

        var errorDescription: String? {
            switch self {
            case let .bundleAlreadyExists(path):
                return String(format: NSLocalizedString("A diagnostics bundle already exists at %@", comment: ""), path)
            }
        }
    }

    static func export(to bundleURL: URL) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: bundleURL.path) else {
            throw ExportError.bundleAlreadyExists(bundleURL.path)
        }

        let tempURL = bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(bundleURL.lastPathComponent).tmp-\(UUID().uuidString)")

        do {
            try fileManager.createDirectory(at: tempURL, withIntermediateDirectories: true, attributes: nil)
            try DiagnosticsReportBuilder.build().write(to: tempURL.appendingPathComponent("report.txt"),
                                                       atomically: true,
                                                       encoding: .utf8)
            try buildRecentLogsSnapshot(maxLines: 400).write(to: tempURL.appendingPathComponent("recent-logs.txt"),
                                                             atomically: true,
                                                             encoding: .utf8)
            try buildManifestData().write(to: tempURL.appendingPathComponent("manifest.json"), options: .atomic)
            try fileManager.moveItem(at: tempURL, to: bundleURL)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
    }

    private static func buildManifestData() throws -> Data {
        let profile = ConfigManager.currentProfileDescriptor()
        let latestLogPath = Logger.shared.logFilePath()
        let manifest = DiagnosticsBundleManifest(generatedAt: Date(),
                                                 appVersion: AppVersionUtil.currentVersion,
                                                 appBuild: AppVersionUtil.currentBuild,
                                                 controllerMode: Settings.isUsingEmbeddedCore ? "embedded" : "external",
                                                 activeProfileName: profile.name,
                                                 activeProfileType: profile.kind.rawValue,
                                                 logFileName: latestLogPath.isEmpty ? nil : URL(fileURLWithPath: latestLogPath).lastPathComponent)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(manifest)
    }

    private static func buildRecentLogsSnapshot(maxLines: Int = 400) throws -> String {
        _ = maxLines // ponytail: DiagnosticsLogReader handles line limit internally
        let latestLogPath = Logger.shared.logFilePath()
        guard !latestLogPath.isEmpty else {
            return NSLocalizedString("No active rolling log file is available yet.", comment: "")
        }

        // ponytail: use DiagnosticsLogReader for bounded tail-read instead of
        // loading the entire log file into memory. Reuses existing tail logic.
        let snapshot = try DiagnosticsLogReader.load(path: latestLogPath,
                                                     filterTitle: NSLocalizedString("All", comment: ""),
                                                     filterToken: nil,
                                                     searchQuery: "",
                                                     paused: false)
        let body = SmartXRedactor.sanitizeText(snapshot.renderedOutput(redactFilePath: true))
        let header = [
            "Recent Logs",
            "-----------",
            "Source File: \(URL(fileURLWithPath: latestLogPath).lastPathComponent)",
            "Redaction: URLs, credentials, tokens, and authorization-style values are sanitized."
        ].joined(separator: "\n")

        return "\(header)\n\n\(body)"
    }
}
