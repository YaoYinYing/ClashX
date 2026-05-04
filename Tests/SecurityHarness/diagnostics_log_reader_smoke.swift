import Foundation

@inline(__always)
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("diagnostics_log_reader_smoke failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum DiagnosticsLogReaderSmokeMain {
    static func main() {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartx-diagnostics-log-smoke-\(UUID().uuidString).log", isDirectory: false)

        do {
            let stalePrefix = String(repeating: "[info] stale-match line that should be dropped by the tail reader\n", count: 20_000)
            let recentLines = (1 ... 260).map { "[error] recent-match-\($0)" }.joined(separator: "\n")
            try (stalePrefix + recentLines).write(to: logURL, atomically: true, encoding: .utf8)

            let snapshot = try DiagnosticsLogReader.load(path: logURL.path,
                                                         filterTitle: "Error",
                                                         filterToken: "[error]",
                                                         searchQuery: "recent-match",
                                                         paused: false)

            expect(snapshot.displayedLineCount == 200, "log reader should cap displayed lines to the last 200 matches")
            expect(snapshot.body.contains("recent-match-260"), "log reader should keep the newest matching lines")
            expect(!snapshot.body.contains("stale-match"), "log reader should not include old lines outside the tail window")

            print("diagnostics_log_reader_smoke passed")
        } catch {
            fputs("diagnostics_log_reader_smoke failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
