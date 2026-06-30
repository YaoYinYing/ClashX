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

    /// Generates an effective config by starting with the base YAML and applying
    /// each active merge layer's operations in order. Script layers are not yet
    /// supported — they require an external script runner.
    ///
    /// ponytail: string-based YAML manipulation via ConfigYAMLEditor. Ceiling:
    /// comments outside target sections are lost; YAML structure not validated.
    /// Upgrade path: YAML parse-emit round-trip with a proper library.
    func generateEffectiveConfig(baseYAML: String) -> (yaml: String, appliedOperations: Int) {
        var result = baseYAML
        var applied = 0

        for layer in orderedActiveLayers {
            guard layer.type == .merge, let ops = layer.mergeOperations else { continue }
            for op in ops {
                switch op.type {
                case .fieldOverride:
                    guard let target = op.target, let value = op.value else { continue }
                    result = ConfigYAMLEditor.upsertSection(
                        named: target, in: result,
                        params: parsedOverrideParams(value),
                        keyOrder: [target]
                    )
                    applied += 1
                case .prependRules, .appendRules:
                    guard let value = op.value else { continue }
                    result = applyRuleOperation(type: op.type, value: value, to: result)
                    applied += 1
                case .prependProxies, .appendProxies,
                     .prependProxyGroups, .appendProxyGroups,
                     .prependRuleProviders, .appendRuleProviders:
                    // These operations require YAML structural awareness
                    // that string manipulation can't safely provide.
                    // Record the intent and skip for now.
                    break
                }
            }
        }

        return (result, applied)
    }

    // MARK: - Private helpers

    /// Parses a simple key=value override string into a dictionary.
    private func parsedOverrideParams(_ raw: String) -> [String: Any] {
        var params: [String: Any] = [:]
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let val = parts[1]
            if val == "true" { params[key] = true }
            else if val == "false" { params[key] = false }
            else if let intVal = Int(val) { params[key] = intVal }
            else { params[key] = val }
        }
        return params
    }

    /// Appends or prepends a rule line to the rules section.
    private func applyRuleOperation(type: ConfigMergeOperation.OperationType, value: String, to yaml: String) -> String {
        let ruleLine: String
        switch type {
        case .prependRules:
            ruleLine = "  - '\(value)'"
        case .appendRules:
            ruleLine = "  - '\(value)'"
        default:
            return yaml
        }

        var lines = yaml.components(separatedBy: "\n")
        guard let rulesIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "rules:" }) else {
            // No rules section: append one with the new rule.
            if let lastNonBlank = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                let insertAt = min(lastNonBlank + 1, lines.count)
                lines.insert(contentsOf: ["", "rules:", ruleLine], at: insertAt)
            } else {
                lines.append(contentsOf: ["rules:", ruleLine])
            }
            return lines.joined(separator: "\n")
        }

        if type == .prependRules {
            lines.insert(ruleLine, at: rulesIdx + 1)
        } else {
            // Append: find the end of the rules block
            var insertAt = rulesIdx + 1
            while insertAt < lines.count {
                let trimmed = lines[insertAt].trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                   !trimmed.hasPrefix("-"), lines[insertAt].first?.isWhitespace == false {
                    break
                }
                insertAt += 1
            }
            lines.insert(ruleLine, at: insertAt)
        }
        return lines.joined(separator: "\n")
    }
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
