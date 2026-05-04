//
//  ConfigValidationIssue.swift
//  ClashX
//
//  Created by Codex on 2026/5/4.
//

import Foundation

struct ConfigValidationIssue: Equatable {
    enum Severity: String {
        /// Contextual note that should be shown to the user, but never block an automated update.
        case info
        /// Non-blocking risk that should be surfaced clearly in the UI.
        case warning
        /// Validation error that should stop an automated update attempt.
        case blocking
    }

    let severity: Severity
    let message: String
}
