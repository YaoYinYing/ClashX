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
}
