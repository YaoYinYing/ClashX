//
//  ProviderHealthHistoryManager.swift
//  ClashX
//
//  Created by Codex on 2026/5/3.
//

import Foundation

struct ProviderHealthHistoryEntry: Codable {
    let timestamp: Date
    let succeededProviders: [String]
    let failedProviders: [String]
    let controllerMode: String
    let controllerURL: String
    let activeProfileName: String
}

enum ProviderHealthHistoryManager {
    private static let maximumEntries = 20

    static func append(succeeded: [String], failed: [String]) {
        var history = loadHistory()
        history.insert(ProviderHealthHistoryEntry(timestamp: Date(),
                                                  succeededProviders: succeeded.sorted(),
                                                  failedProviders: failed.sorted(),
                                                  controllerMode: Settings.isUsingEmbeddedCore ? "embedded" : "external",
                                                  controllerURL: redactedControllerURL(),
                                                  activeProfileName: ConfigManager.selectConfigName),
                       at: 0)
        if history.count > maximumEntries {
            history = Array(history.prefix(maximumEntries))
        }
        persist(history)
    }

    static func loadHistory() -> [ProviderHealthHistoryEntry] {
        guard let data = try? Data(contentsOf: Paths.providerHealthHistoryURL) else { return [] }
        return (try? JSONDecoder.providerHistory.decode([ProviderHealthHistoryEntry].self, from: data)) ?? []
    }

    static func summary(limit: Int = 5) -> String {
        let history = Array(loadHistory().prefix(limit))
        guard !history.isEmpty else {
            return "Provider Health History\n-----------------------\nNo persisted provider health history is available yet."
        }

        var lines = [
            "Provider Health History",
            "-----------------------"
        ]

        for entry in history {
            let timestamp = DateFormatter.localizedString(from: entry.timestamp, dateStyle: .short, timeStyle: .medium)
            lines.append("\(timestamp) [\(entry.controllerMode)] profile=\(entry.activeProfileName) controller=\(entry.controllerURL)")
            lines.append("  succeeded: \(entry.succeededProviders.isEmpty ? "none" : entry.succeededProviders.joined(separator: ", "))")
            lines.append("  failed: \(entry.failedProviders.isEmpty ? "none" : entry.failedProviders.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    private static func persist(_ history: [ProviderHealthHistoryEntry]) {
        do {
            try FileManager.default.createDirectory(at: Paths.smartXDiagnosticsDirectoryURL,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
            let data = try JSONEncoder.providerHistory.encode(history)
            try data.write(to: Paths.providerHealthHistoryURL, options: .atomic)
        } catch {
            Logger.log("Failed to persist provider health history: \(error.localizedDescription)", level: .warning)
        }
    }

    private static func redactedControllerURL() -> String {
        guard let components = URLComponents(string: Settings.activeControllerURL) else {
            return "unavailable"
        }

        let host = components.host ?? "unknown"
        if let port = components.port, let scheme = components.scheme {
            return "\(scheme)://\(host):\(port)"
        }
        if let scheme = components.scheme {
            return "\(scheme)://\(host)"
        }
        return host
    }
}

private extension JSONEncoder {
    static let providerHistory: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let providerHistory: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
