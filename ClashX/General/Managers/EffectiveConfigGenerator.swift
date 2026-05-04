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

enum EffectiveConfigGenerationResult {
    case unsupported(reason: String)

    var isGenerated: Bool {
        false
    }
}

enum EffectiveConfigGenerator {
    static func generateLightGBMManagedOverrideEffectiveConfig(baseConfigURL: URL,
                                                               managedOverride: SmartXManagedOverride?) -> EffectiveConfigGenerationResult {
        let reason = NSLocalizedString("Generated effective config is still unsupported because SmartX does not yet have a safe YAML emitter for base config plus managed LightGBM override.", comment: "")
        Logger.log("Effective config generation remains unsupported for \(baseConfigURL.lastPathComponent); safe YAML emit path is still missing.", level: .info)
        _ = managedOverride
        return .unsupported(reason: reason)
    }
}
