//
//  SmartXManagedOverrideModel.swift
//  ClashX
//
//  Created by Codex on 2026/5/15.
//

import Foundation

struct SmartXManagedOverride: Codable {
    // Keep schema 1 intentionally small for compatibility. Adding metadata such as
    // updatedAt or lastWrittenBy would widen migration surface before the real
    // effective-config pipeline exists, so this groundwork file only stores the
    // override fields SmartX needs today.
    var schemaVersion: Int
    var lightGBM: LightGBMOverride?
}

struct LightGBMOverride: Codable {
    var enabled: Bool
    var modelURL: String
    var autoUpdate: Bool
    var updateIntervalHours: Int
}
