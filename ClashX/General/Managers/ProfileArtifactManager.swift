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
    let requestedSmartXOverrides: Bool
    let emittedSmartXOverrides: Bool
    let includesProfileMerge: Bool
    let includesRuntimeOverrides: Bool

    private enum CodingKeys: String, CodingKey {
        case selectedProfileName
        case selectedProfileKind
        case sourceConfigPath
        case sourceRemoteURL
        case generatedAt
        case controllerMode
        case generationMode
        case requestedSmartXOverrides
        case emittedSmartXOverrides
        case includesSmartXOverrides
        case includesProfileMerge
        case includesRuntimeOverrides
    }

    init(selectedProfileName: String,
         selectedProfileKind: String,
         sourceConfigPath: String,
         sourceRemoteURL: String?,
         generatedAt: Date,
         controllerMode: String,
         generationMode: String,
         requestedSmartXOverrides: Bool,
         emittedSmartXOverrides: Bool,
         includesProfileMerge: Bool,
         includesRuntimeOverrides: Bool) {
        self.selectedProfileName = selectedProfileName
        self.selectedProfileKind = selectedProfileKind
        self.sourceConfigPath = sourceConfigPath
        self.sourceRemoteURL = sourceRemoteURL
        self.generatedAt = generatedAt
        self.controllerMode = controllerMode
        self.generationMode = generationMode
        self.requestedSmartXOverrides = requestedSmartXOverrides
        self.emittedSmartXOverrides = emittedSmartXOverrides
        self.includesProfileMerge = includesProfileMerge
        self.includesRuntimeOverrides = includesRuntimeOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedProfileName = try container.decode(String.self, forKey: .selectedProfileName)
        selectedProfileKind = try container.decode(String.self, forKey: .selectedProfileKind)
        sourceConfigPath = try container.decode(String.self, forKey: .sourceConfigPath)
        sourceRemoteURL = try container.decodeIfPresent(String.self, forKey: .sourceRemoteURL)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        controllerMode = try container.decode(String.self, forKey: .controllerMode)
        generationMode = try container.decode(String.self, forKey: .generationMode)
        let legacyOverrideFlag = try container.decodeIfPresent(Bool.self, forKey: .includesSmartXOverrides) ?? false
        requestedSmartXOverrides = try container.decodeIfPresent(Bool.self, forKey: .requestedSmartXOverrides) ?? legacyOverrideFlag
        emittedSmartXOverrides = try container.decodeIfPresent(Bool.self, forKey: .emittedSmartXOverrides) ?? false
        includesProfileMerge = try container.decodeIfPresent(Bool.self, forKey: .includesProfileMerge) ?? false
        includesRuntimeOverrides = try container.decodeIfPresent(Bool.self, forKey: .includesRuntimeOverrides) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedProfileName, forKey: .selectedProfileName)
        try container.encode(selectedProfileKind, forKey: .selectedProfileKind)
        try container.encode(sourceConfigPath, forKey: .sourceConfigPath)
        try container.encodeIfPresent(sourceRemoteURL, forKey: .sourceRemoteURL)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(controllerMode, forKey: .controllerMode)
        try container.encode(generationMode, forKey: .generationMode)
        try container.encode(requestedSmartXOverrides, forKey: .requestedSmartXOverrides)
        try container.encode(emittedSmartXOverrides, forKey: .emittedSmartXOverrides)
        try container.encode(includesProfileMerge, forKey: .includesProfileMerge)
        try container.encode(includesRuntimeOverrides, forKey: .includesRuntimeOverrides)
    }
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
                                               requestedSmartXOverrides: false,
                                               emittedSmartXOverrides: false,
                                               includesProfileMerge: false,
                                               includesRuntimeOverrides: false)

        do {
            try ensureArtifactsDirectory()
            try copyArtifact(from: sourceConfigPath, to: Paths.successfulReloadArtifactURL)
            try copyArtifact(from: sourceConfigPath, to: Paths.lastKnownGoodConfigURL)
            try writeMetadata(metadata, to: Paths.successfulReloadMetadataURL)
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
