//
//  ProfileArtifactManager.swift
//  ClashX
//
//  Created by Codex on 2026/5/2.
//

import Foundation

struct ProfileArtifactMetadata: Codable {
    let selectedProfileName: String
    let selectedProfileKind: String
    let sourceConfigPath: String
    let sourceRemoteURL: String?
    let generatedAt: Date
    let controllerMode: String
    let generationMode: String
    let includesSmartXOverrides: Bool
    let includesProfileMerge: Bool
    let includesRuntimeOverrides: Bool
}

enum ProfileArtifactManager {
    static func persistSuccessfulReloadArtifacts(configName: String, sourceConfigPath: String, originalSourceConfigPath: String? = nil) {
        let profile = ConfigManager.profileDescriptor(name: configName)
        let metadata = ProfileArtifactMetadata(selectedProfileName: profile.name,
                                               selectedProfileKind: profile.kind.rawValue,
                                               sourceConfigPath: originalSourceConfigPath ?? sourceConfigPath,
                                               sourceRemoteURL: profile.remoteURL,
                                               generatedAt: Date(),
                                               controllerMode: Settings.isUsingEmbeddedCore ? "embedded" : "external",
                                               generationMode: "source-copy",
                                               includesSmartXOverrides: false,
                                               includesProfileMerge: false,
                                               includesRuntimeOverrides: false)

        do {
            try ensureArtifactsDirectory()
            try copyArtifact(from: sourceConfigPath, to: Paths.generatedEffectiveConfigURL)
            try copyArtifact(from: sourceConfigPath, to: Paths.lastKnownGoodConfigURL)
            try writeMetadata(metadata, to: Paths.generatedEffectiveMetadataURL)
            try writeMetadata(metadata, to: Paths.lastKnownGoodMetadataURL)
        } catch {
            Logger.log("Failed to persist profile artifacts: \(error.localizedDescription)", level: .warning)
        }
    }

    static func loadMetadata(at url: URL) -> ProfileArtifactMetadata? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProfileArtifactMetadata.self, from: data)
    }

    private static func ensureArtifactsDirectory() throws {
        try FileManager.default.createDirectory(at: Paths.smartXArtifactsDirectoryURL,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
    }

    private static func copyArtifact(from sourcePath: String, to targetURL: URL) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath, isDirectory: false))
        try data.write(to: targetURL, options: .atomic)
    }

    private static func writeMetadata(_ metadata: ProfileArtifactMetadata, to targetURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        try data.write(to: targetURL, options: .atomic)
    }
}
