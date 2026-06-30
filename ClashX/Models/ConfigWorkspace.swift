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

    /// Generates effective config from base YAML + active merge layer overrides.
    /// Supported: fieldOverride (via ConfigYAMLEditor.upsertSection),
    /// prependRules/appendRules. Unsupported operations skip safely.
    ///
    /// ponytail: string-based. Ceiling: comments lost, no YAML validation.
    /// Upgrade path: YAML parse-emit library when TUN editors need round-trips.
    func generateEffectiveConfig(baseYAML: String) -> String {
        var result = baseYAML
        for layer in orderedActiveLayers {
            guard layer.type == .merge, let ops = layer.mergeOperations else { continue }
            for op in ops {
                switch op.type {
                case .fieldOverride:
                    guard let target = op.target, let value = op.value else { continue }
                    result = ConfigYAMLEditor.upsertSection(
                        named: target, in: result,
                        params: parseOverrideParams(value),
                        keyOrder: [target]
                    )
                case .prependRules, .appendRules:
                    guard let value = op.value else { continue }
                    result = applyRuleOp(type: op.type, value: value, to: result)
                default: break // skip unsupported
                }
            }
        }
        return result
    }
}

// ponytail: file-level helpers for generateEffectiveConfig.
// Internal — used by ConfigPipeline.generateEffectiveConfig().

func parseOverrideParams(_ raw: String) -> [String: Any] {
    var params: [String: Any] = [:]
    for pair in raw.split(separator: ",") {
        let kv = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard kv.count == 2 else { continue }
        let v = kv[1]
        if v == "true" { params[String(kv[0])] = true }
        else if v == "false" { params[String(kv[0])] = false }
        else if let n = Int(v) { params[String(kv[0])] = n }
        else { params[String(kv[0])] = v }
    }
    return params
}

func applyRuleOp(type: ConfigMergeOperation.OperationType, value: String, to yaml: String) -> String {
    var lines = yaml.components(separatedBy: "\n")
    let ruleLine = "  - '\(value)'"
    if let idx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "rules:" }) {
        lines.insert(ruleLine, at: type == .prependRules ? idx + 1 : {
            var i = idx + 1
            while i < lines.count, lines[i].first?.isWhitespace == true { i += 1 }
            return i
        }())
    } else {
        lines.append(contentsOf: ["", "rules:", ruleLine])
    }
    return lines.joined(separator: "\n")
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
