//
//  EffectiveConfigGenerator.swift
//  ClashX
//
//  Created by Codex on 2026/5/4.
//
//  Current scope is intentionally narrow. SmartX does not yet have a safe YAML
//  parse-emit path for generating a full effective config from profile source
//  plus managed overrides, so this interface reports that limitation explicitly.
//

import Foundation

struct EffectiveConfigGenerationRequest {
    let baseConfigURL: URL
    let managedOverride: SmartXManagedOverride?
}

struct EffectiveConfigGenerationProvenance {
    let baseConfigPath: String
    let hasManagedOverride: Bool
    let requestedSmartXOverrides: Bool
    let emittedSmartXOverrides: Bool
    let includesProfileMerge: Bool
    let generationMode: String
    let reason: String
}

enum EffectiveConfigGenerationResult {
    case generated(url: URL, provenance: EffectiveConfigGenerationProvenance)
    case unsupported(reason: String, provenance: EffectiveConfigGenerationProvenance)
    case failed(reason: String, provenance: EffectiveConfigGenerationProvenance)

    var isGenerated: Bool {
        if case .generated = self {
            return true
        }
        return false
    }

    var provenance: EffectiveConfigGenerationProvenance {
        switch self {
        case let .generated(_, provenance),
             let .unsupported(_, provenance),
             let .failed(_, provenance):
            return provenance
        }
    }

    var reason: String {
        switch self {
        case let .generated(_, provenance):
            return provenance.reason
        case let .unsupported(reason, _), let .failed(reason, _):
            return reason
        }
    }
}

enum EffectiveConfigGenerator {
    static func generate(_ request: EffectiveConfigGenerationRequest) -> EffectiveConfigGenerationResult {
        let reason = NSLocalizedString("Generated effective config is still unsupported because SmartX does not yet have a safe YAML emitter for base config plus managed LightGBM override.", comment: "")
        let requestedSmartXOverrides = request.managedOverride?.lightGBM != nil
        let provenance = EffectiveConfigGenerationProvenance(baseConfigPath: request.baseConfigURL.path,
                                                             hasManagedOverride: request.managedOverride != nil,
                                                             requestedSmartXOverrides: requestedSmartXOverrides,
                                                             emittedSmartXOverrides: false,
                                                             includesProfileMerge: false,
                                                             generationMode: "unsupported-safe-yaml-emitter-missing",
                                                             reason: reason)
        Logger.log("Effective config generation remains unsupported for \(request.baseConfigURL.lastPathComponent); safe YAML emit path is still missing.", level: .info)
        return .unsupported(reason: reason, provenance: provenance)
    }

    static func generateLightGBMManagedOverrideEffectiveConfig(baseConfigURL: URL,
                                                               managedOverride: SmartXManagedOverride?) -> EffectiveConfigGenerationResult {
        generate(EffectiveConfigGenerationRequest(baseConfigURL: baseConfigURL,
                                                  managedOverride: managedOverride))
    }
}
