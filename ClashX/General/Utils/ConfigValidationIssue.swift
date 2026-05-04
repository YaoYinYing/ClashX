//
//  ConfigValidationIssue.swift
//  ClashX
//
//  Created by Codex on 2026/5/4.
//

import Foundation

struct ConfigValidationIssue: Equatable {
    enum Severity: String {
        case info
        case warning
        case blocking
    }

    let severity: Severity
    let message: String
}
