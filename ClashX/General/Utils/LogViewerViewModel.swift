//
//  LogViewerViewModel.swift
//  ClashX
//
//  Extracted from DiagnosticsDashboardViewController (Phase 4 decomposition).
//  Manages log file loading, level/search filtering, pause state, and
//  auto-refresh timer so the dashboard only owns UI presentation.
//
//  ponytail: single-consumer view model. Ceiling: the timer remains on the
//  main thread because the dashboard renders directly from the output string.
//  Upgrade path: move to background queue when maxTailBytes increases or
//  richer parsing is added.

import Foundation

enum LogLevelFilter: Int, CaseIterable {
    case all
    case error
    case warning
    case info
    case debug

    var title: String {
        switch self {
        case .all: return NSLocalizedString("All", comment: "")
        case .error: return NSLocalizedString("Error", comment: "")
        case .warning: return NSLocalizedString("Warning", comment: "")
        case .info: return NSLocalizedString("Info", comment: "")
        case .debug: return NSLocalizedString("Debug", comment: "")
        }
    }

    var token: String? {
        switch self {
        case .all: return nil
        case .error: return "[error]"
        case .warning: return "[warning]"
        case .info: return "[info]"
        case .debug: return "[debug]"
        }
    }
}

final class LogViewerViewModel {
    private(set) var output: String = NSLocalizedString("Logs not loaded.", comment: "")
    private(set) var snapshot: DiagnosticsLogSnapshot?
    private var timer: Timer?
    private var isPaused = false
    var redactContent = false

    var onOutputChanged: (() -> Void)?

    var paused: Bool {
        isPaused
    }

    var displayOutput: String {
        redactContent ? SmartXRedactor.sanitizeText(output) : output
    }

    func togglePause() {
        isPaused.toggle()
        if !isPaused {
            refresh(announce: false)
        }
    }

    func startAutoRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            self.refresh(announce: false)
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    func refresh(levelIndex: Int = 0, searchQuery: String = "", announce: Bool = true) -> String? {
        let path = Logger.shared.logFilePath()
        guard !path.isEmpty else {
            snapshot = nil
            output = NSLocalizedString("No active log file is available yet.", comment: "")
            onOutputChanged?()
            return announce ? output : nil
        }

        do {
            let filter = LogLevelFilter(rawValue: levelIndex) ?? .all
            let s = try DiagnosticsLogReader.load(path: path,
                                                  filterTitle: filter.title,
                                                  filterToken: filter.token,
                                                  searchQuery: searchQuery,
                                                  paused: isPaused)
            snapshot = s
            output = s.renderedOutput()
            onOutputChanged?()
            return announce ? NSLocalizedString("Log viewer refreshed from the current rolling log file.", comment: "") : nil
        } catch {
            snapshot = nil
            output = String(format: NSLocalizedString("The current log file could not be read: %@", comment: ""), path)
            onOutputChanged?()
            return announce ? NSLocalizedString("Failed to read the current log file.", comment: "") : nil
        }
    }
}
