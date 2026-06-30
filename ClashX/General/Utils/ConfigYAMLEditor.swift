//
//  ConfigYAMLEditor.swift
//  ClashX
//
//  Shared YAML section helper extracted from TUN/DNS config editors.
//  Replaces duplicated upsertSection and renderSection methods.
//
//  ponytail: string-based YAML manipulation. Ceiling: comments in the target
//  section are lost on rewrite, non-standard indent normalized.
//  Upgrade path: replace with YAML parse-emit round-trip when the config
//  workspace pipeline (Phase 9) supports it.

import Foundation

enum ConfigYAMLEditor {
    /// Inserts or updates a top-level YAML section by key name, preserving
    /// all other sections and comments outside the target section.
    static func upsertSection(named sectionKey: String,
                              in yaml: String,
                              params: [String: Any],
                              keyOrder: [String]) -> String {
        let sectionYaml = renderSection(named: sectionKey, params: params, keyOrder: keyOrder)
        var lines = yaml.components(separatedBy: "\n")
        var sectionStart: Int?
        var sectionEnd: Int?

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "\(sectionKey):" || trimmed.hasPrefix("\(sectionKey):") {
                sectionStart = idx
                continue
            }
            if sectionStart != nil, sectionEnd == nil {
                if !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                   line.first?.isWhitespace == false {
                    sectionEnd = idx
                    break
                }
            }
        }

        if let start = sectionStart {
            let end = sectionEnd ?? lines.count
            lines.replaceSubrange(start ..< end, with: [sectionYaml])
        } else {
            if let lastNonBlank = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                let insertAt = min(lastNonBlank + 1, lines.count)
                if insertAt < lines.count, lines[insertAt].trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.insert(sectionYaml, at: insertAt)
                } else {
                    lines.append("")
                    lines.append(sectionYaml)
                }
            } else {
                lines.append(sectionYaml)
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Renders a parameter dictionary as a YAML section block.
    static func renderSection(named sectionKey: String,
                              params: [String: Any],
                              keyOrder: [String]) -> String {
        var result = "\(sectionKey):"
        for key in keyOrder {
            guard let value = params[key] else { continue }
            switch value {
            case let b as Bool:
                result += "\n  \(key): \(b ? "true" : "false")"
            case let s as String:
                result += "\n  \(key): \"\(s)\""
            case let arr as [String]:
                if arr.isEmpty { continue }
                result += "\n  \(key):"
                for item in arr {
                    result += "\n    - \"\(item)\""
                }
            case let n as Int:
                result += "\n  \(key): \(n)"
            default:
                break
            }
        }
        return result
    }
}
