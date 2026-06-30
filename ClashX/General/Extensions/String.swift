//
//  String.swift
//  ClashX
//
//  Created by SmartX on 2026/04/24.
//

import Foundation

extension String {
    /// Decode text data exported by legacy APIs that used UTF-16/"Unicode" NSString encoding.
    static func decodeLegacyUnicode(_ data: Data) -> String? {
        return NSString(data: data, encoding: String.Encoding.utf16.rawValue) as String?
    }

    /// Returns nil for an empty string, otherwise returns self.
    /// ponytail: extracted from duplicated private extensions in TUN/DNS editors.
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
