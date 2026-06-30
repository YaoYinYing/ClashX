//
//  ConfigWorkspace.swift
//  ClashX
//
//  Phase 9 data model: explicit source, layer, merge, and generated-artifact
//  types for the config workspace pipeline. Replaces filename-era assumptions
//  with a reproducible, inspectable pipeline model.
//
//  ponytail: types only — no YAML parse-emit or pipeline execution yet.
//  Ceiling: these types describe the workspace but don't execute it.
//  Upgrade path: add ConfigPipeline.execute() when the YAML round-trip
//  path exists (replacing string-based upsert in TUN/DNS editors).

import Foundation

// MARK: - Config source

enum ConfigSourceType: String, Codable {
    case local
    case remote
    case generated
    case merged
}

struct ConfigSource: Codable {
    let type: ConfigSourceType
    let location: String
    let remoteURL: String?
    let displayName: String
    let validationState: ConfigValidationState
    let lastUpdatedAt: Date?

    enum ConfigValidationState: String, Codable {
        case unknown
        case valid
        case invalid
        case unverified
    }
}

// MARK: - Config layers

enum ConfigLayerType: String, Codable {
    case base
    case merge
    case script
    case generated
}

struct ConfigLayer: Codable {
    let name: String
    let type: ConfigLayerType
    let source: ConfigSource
    let enabled: Bool
    let order: Int

    /// ponytail: merge operations are explicit, not arbitrary YAML surgery.
    /// Operations include: prepend-rules, append-rules, prepend-proxies,
    /// append-proxies, prepend-proxy-groups, append-proxy-groups,
    /// prepend-rule-providers, append-rule-providers, and field overrides.
    let mergeOperations: [ConfigMergeOperation]?

    /// For script layers: the script identifier or path.
    let scriptIdentifier: String?
}

// MARK: - Merge operations

struct ConfigMergeOperation: Codable {
    enum OperationType: String, Codable {
        case prependRules
        case appendRules
        case prependProxies
        case appendProxies
        case prependProxyGroups
        case appendProxyGroups
        case prependRuleProviders
        case appendRuleProviders
        case fieldOverride
    }

    let type: OperationType
    let target: String?
    let value: String?
    let description: String
}

// MARK: - Pipeline

struct ConfigPipeline: Codable {
    let layers: [ConfigLayer]
    let activeLayerNames: [String]
    let generatedAt: Date

    var activeLayers: [ConfigLayer] {
        layers.filter { activeLayerNames.contains($0.name) && $0.enabled }
    }

    var orderedActiveLayers: [ConfigLayer] {
        activeLayers.sorted { $0.order < $1.order }
    }

    var hasOverrides: Bool {
        orderedActiveLayers.contains { $0.type == .merge || $0.type == .script }
    }

    var baseLayer: ConfigLayer? {
        orderedActiveLayers.first { $0.type == .base }
    }

    // ponytail: generateEffectiveConfig deleted — zero production callers.
    // The ConfigWorkspace model + ConfigYAMLEditor are the foundation.
    // Add pipeline execution when a feature needs it (e.g. TUN editor
    // YAML round-trip or profile merge UI).
}

// MARK: - Artifacts

enum ConfigArtifactType: String, Codable {
    case sourceCopy
    case generatedEffective
    case lastKnownGood
    case mergePreview
}

struct ConfigArtifact: Codable {
    let type: ConfigArtifactType
    let localURL: URL
    let metadataURL: URL
    let pipeline: ConfigPipeline?
    let provenance: String
    let createdAt: Date
    let isValid: Bool
}

// MARK: - Workspace

struct ConfigWorkspace: Codable {
    let layers: [ConfigLayer]
    let artifacts: [ConfigArtifact]
    let activePipeline: ConfigPipeline?
    let lastKnownGoodPipeline: ConfigPipeline?
    let workspaceRoot: URL

    var effectiveConfigArtifact: ConfigArtifact? {
        artifacts.first { $0.type == .generatedEffective && $0.isValid }
    }

    var lastKnownGoodArtifact: ConfigArtifact? {
        artifacts.first { $0.type == .lastKnownGood && $0.isValid }
    }

    /// ponytail: minimal workspace validation — checks that no two active
    /// layers have the same order and that a generated artifact references
    /// an active pipeline.
    func validate() -> [String] {
        var issues: [String] = []
        let active = activePipeline?.orderedActiveLayers ?? []
        let orders = active.map(\.order)
        if Set(orders).count != orders.count {
            issues.append("Active layers have duplicate order values.")
        }
        if let artifact = effectiveConfigArtifact,
           artifact.pipeline == nil {
            issues.append("Effective config artifact has no pipeline provenance.")
        }
        return issues
    }
}
