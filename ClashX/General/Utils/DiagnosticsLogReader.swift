//
//  DiagnosticsLogReader.swift
//  ClashX
//
//  Created by Codex on 2026/5/4.
//

import Foundation

struct DiagnosticsLogSnapshot {
    let filePath: String
    let filterTitle: String
    let searchQuery: String
    let paused: Bool
    let matchedLineCount: Int
    let displayedLineCount: Int
    let body: String

    func renderedOutput() -> String {
        let header = [
            "File: \(filePath)",
            "Filter: \(filterTitle)",
            "Search: \(searchQuery.isEmpty ? "none" : searchQuery)",
            "Paused: \(paused ? "yes" : "no")",
            "Lines: \(matchedLineCount) showing last \(displayedLineCount)"
        ].joined(separator: "\n")
        return "\(header)\n\n\(body)"
    }
}

enum DiagnosticsLogReader {
    static let maxTailBytes = 1_048_576
    static let maxDisplayedLines = 200

    static func load(path: String, filterTitle: String, filterToken: String?, searchQuery: String, paused: Bool) throws -> DiagnosticsLogSnapshot {
        let rawTail = try tailString(path: path, maxBytes: maxTailBytes)
        let search = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = rawTail
            .components(separatedBy: .newlines)
            .filter { line in
                let matchesLevel = filterToken.map { line.localizedCaseInsensitiveContains($0) } ?? true
                let matchesSearch = search.isEmpty || line.lowercased().contains(search)
                return matchesLevel && matchesSearch
            }

        let tail = Array(filtered.suffix(maxDisplayedLines))
        let body = tail.isEmpty
            ? NSLocalizedString("No log lines match the current filter.", comment: "")
            : tail.joined(separator: "\n")

        return DiagnosticsLogSnapshot(filePath: path,
                                      filterTitle: filterTitle,
                                      searchQuery: search,
                                      paused: paused,
                                      matchedLineCount: filtered.count,
                                      displayedLineCount: tail.count,
                                      body: body)
    }

    private static func tailString(path: String, maxBytes: Int) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer {
            fileHandle.closeFile()
        }

        let fileSize = Int(fileHandle.seekToEndOfFile())
        let offset = max(0, fileSize - maxBytes)
        fileHandle.seek(toFileOffset: UInt64(offset))
        let data = fileHandle.readDataToEndOfFile()
        var text = String(decoding: data, as: UTF8.self)

        if offset > 0, let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        }

        return text
    }
}
