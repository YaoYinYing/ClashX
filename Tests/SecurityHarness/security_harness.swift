import Foundation

enum NameError: Error { case invalid }

func safeConfigName(_ raw: String) throws -> String {
    let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !candidate.isEmpty else { throw NameError.invalid }
    guard candidate.count <= 80 else { throw NameError.invalid }
    guard candidate != ".", candidate != "..", !candidate.hasPrefix(".") else { throw NameError.invalid }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " _-."))
    for scalar in candidate.unicodeScalars {
        if scalar.value == 0 || CharacterSet.controlCharacters.contains(scalar) || !allowed.contains(scalar) {
            throw NameError.invalid
        }
    }
    return candidate
}

func deterministicFallbackName(sourceURL: String) -> String {
    var hash: UInt64 = 1469598103934665603
    for byte in sourceURL.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1099511628211
    }
    let suffix = String(format: "%08llx", hash & 0xFFFFFFFF)
    return "remote-config-\(suffix)"
}

func safeNameFromSuggestedFilename(_ suggested: String?, sourceURL: String) -> String {
    if let suggested {
        let base = URL(fileURLWithPath: suggested).deletingPathExtension().lastPathComponent
        if let safe = try? safeConfigName(base) {
            return safe
        }
    }
    return deterministicFallbackName(sourceURL: sourceURL)
}

func writeConfigAtomically(content: String, targetURL: URL, verify: (String) -> Bool) throws {
    let fileManager = FileManager.default
    let baseDir = targetURL.deletingLastPathComponent()
    let tempURL = baseDir.appendingPathComponent(".\(UUID().uuidString).tmp.yaml")
    try content.write(to: tempURL, atomically: true, encoding: .utf8)
    guard verify(content) else {
        try? fileManager.removeItem(at: tempURL)
        throw NameError.invalid
    }
    if fileManager.fileExists(atPath: targetURL.path) {
        _ = try fileManager.replaceItemAt(targetURL, withItemAt: tempURL)
    } else {
        try fileManager.moveItem(at: tempURL, to: targetURL)
    }
}

func assertPass(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func assertThrows(_ message: String, _ block: () throws -> Void) {
    do {
        try block()
        fputs("FAIL: expected throw - \(message)\n", stderr)
        exit(1)
    } catch {}
}

// Required checks
assertThrows("../evil should fail") { _ = try safeConfigName("../evil") }
assertThrows(".hidden should fail") { _ = try safeConfigName(".hidden") }
assertPass((try? safeConfigName("default")) == "default", "default should pass")
assertPass((try? safeConfigName("My Config")) == "My Config", "My Config should pass")
assertPass((try? safeConfigName("proxy-us-1")) == "proxy-us-1", "proxy-us-1 should pass")
assertPass((try? safeConfigName("test.profile")) == "test.profile", "test.profile should pass")

let fallbackA = safeNameFromSuggestedFilename("../../evil.yaml", sourceURL: "https://one.example/sub")
let fallbackB = safeNameFromSuggestedFilename("../../evil.yaml", sourceURL: "https://two.example/sub")
assertPass(!fallbackA.contains(".."), "fallback should not contain unsafe raw name")
let deterministicA = safeNameFromSuggestedFilename(nil, sourceURL: "https://one.example/sub")
let deterministicB = safeNameFromSuggestedFilename(nil, sourceURL: "https://two.example/sub")
assertPass(deterministicA == safeNameFromSuggestedFilename(nil, sourceURL: "https://one.example/sub"), "fallback should be deterministic")
assertPass(deterministicA != deterministicB, "different source URLs should have different fallback names")

let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("security-harness-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tempDir) }
let target = tempDir.appendingPathComponent("config.yaml")
try "old: true\n".write(to: target, atomically: true, encoding: .utf8)

do {
    try writeConfigAtomically(content: "", targetURL: target) { !$0.isEmpty }
    fputs("FAIL: invalid content should fail verification\n", stderr)
    exit(1)
} catch {
    let current = try String(contentsOf: target, encoding: .utf8)
    assertPass(current == "old: true\n", "failed update must preserve existing config")
}

print("Security harness checks passed")
