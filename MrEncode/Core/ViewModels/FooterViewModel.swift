//
//  FooterViewModel.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/23/25.
//

//
// MARK: - FooterViewModel.swift
//

import Foundation
import SwiftUI
import Combine

/// Handles footer-specific UI logic and status formatting
@MainActor
class FooterViewModel: ObservableObject {
    private let core = AppCore.shared
    private var cancellables = Set<AnyCancellable>()
    private let estimateQueue = DispatchQueue(label: "mrencode.footer.estimate", qos: .userInitiated)
    private var pendingCoreForward: Task<Void, Never>? = nil

    // Async, non-blocking footer estimate string
    @Published var timeEstimateText: String? = nil

    init() {
        core.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }

    // Call this once from the footer view (e.g., .onAppear) to wire async, debounced recompute
    func bind(to state: AppState) {
        // Capture values on the main actor
        let filesSnapshot = state.files
        let settingsSnapshot = state.settings
        recomputeEstimateAsync(files: filesSnapshot, settings: settingsSnapshot)

        // Debounce any UI/core changes surfaced via AppState
        state.objectWillChange
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    guard let self else { return }
                    // Ensure we read state on the main actor
                    let filesSnapshot = state.files
                    let settingsSnapshot = state.settings
                    self.recomputeEstimateAsync(files: filesSnapshot, settings: settingsSnapshot)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Status Display Logic

    func formatStatusLine(files: [MediaItem], hasSelection: Bool, runMode: RunMode) -> String {
        // NOTE: hasSelection previously implied sub-filtering by selectedIDs,
        // but the prior implementation wasn't actually using selectedIDs.
        // We keep your existing logic but clarify it here.
        let targetFiles = files

        let queued   = targetFiles.filter { $0.status == .queued   && $0.isChecked }.count
        let encoding = targetFiles.filter { $0.status == .encoding }.count
        let done     = targetFiles.filter { $0.status == .done     }.count
        let blocked  = targetFiles.filter { $0.status == .blocked  }.count
        let errors   = targetFiles.filter { $0.status == .error    }.count

        var parts: [String] = []

        if encoding > 0 {
            let verb = runMode == .localNative ? "encoding" : "submitted"
            parts.append("\(encoding) \(verb)")
        }
        if queued > 0   { parts.append("\(queued) queued") }
        if done > 0     { parts.append("\(done) done") }
        if blocked > 0  { parts.append("\(blocked) blocked") }
        if errors > 0   { parts.append("\(errors) errors") }

        return parts.isEmpty ? "Ready" : parts.joined(separator: " • ")
    }

    // MARK: - Async Time Estimate (replaces blocking path)

    private func recomputeEstimateAsync(files: [MediaItem], settings: Settings) {
        // Only estimate items the user has actually queued & checked (matches your encode path)
        let candidates = files.filter { $0.status == .queued && $0.isChecked }
        guard !candidates.isEmpty else {
            timeEstimateText = nil
            return
        }

        // Lightweight immediate placeholder; no blocking on main
        timeEstimateText = "Calculating…"

        estimateQueue.async { [weak self] in
            guard let self else { return }

            var totalSeconds: Double = 0
            var totalBytes: Int64 = 0
            var counted = 0

            // Avoid AVAsset here; rely on metadata you already have + your estimator
            for item in candidates {
                if item.meta.durationSeconds > 0 {
                    totalSeconds += item.meta.durationSeconds
                }
                if let est = OutputEstimator.estimate(basics: nil, meta: item.meta, settings: settings) {
                    // est = (_, _, totalBps, estBytes, _, _)
                    totalBytes += Int64(est.3)
                }
                counted += 1
            }

            // Format off-main results on main
            DispatchQueue.main.async {
                self.timeEstimateText = self.formatTotals(totalSeconds: totalSeconds,
                                                          totalBytes: totalBytes,
                                                          jobsCount: counted,
                                                          runMode: settings.runMode)
            }
        }
    }

    private func formatTotals(totalSeconds: Double,
                              totalBytes: Int64,
                              jobsCount: Int,
                              runMode: RunMode) -> String? {
        guard jobsCount > 0 else { return nil }

        let sizeStr = formatFileSize(totalBytes)
        let jobsStr = "\(jobsCount) job" + (jobsCount == 1 ? "" : "s")

        // Keep copy simple & snappy; you can swap in EncodeTimeEstimator later if you like
        switch runMode {
        case .localNative:
            // If you want ETA, plug in your EncodeTimeEstimator to turn totalSeconds into a time string.
            return "~\(sizeStr) total • \(jobsStr)"
        case .remoteDeadline:
            // Farm speed varies; show size and job count
            return "\(sizeStr) total • \(jobsStr) (farm)"
        }
    }

    // Back-compat shim so existing footer can compile if it still calls this synchronously.
    // Prefer reading `timeEstimateText` directly in the view.
    func formatTimeEstimate(files: [MediaItem], hasSelection: Bool, settings: Settings) -> String? {
        return timeEstimateText
    }

    // MARK: - Global (Batch) Progress

    private func batchParticipants(files: [MediaItem]) -> [MediaItem] {
        files.filter { item in
            if item.status == .blocked { return false }
            if item.status == .queued { return item.isChecked }
            return (item.status == .encoding || item.status == .done || item.status == .error)
        }
    }

    /// Footer/global progress is only meaningful when an encode is *actively running*
    /// and we have a true batch (2+ participants).
    func shouldShowFooterBatchProgress(files: [MediaItem]) -> Bool {
        let isEncodingNow = files.contains { $0.status == .encoding }
        guard isEncodingNow else { return false }

        // True batch = more than one participating job in the current run
        return batchParticipants(files: files).count > 1
    }

    func globalProgress(files: [MediaItem]) -> Double {
        let participants = batchParticipants(files: files)
        guard !participants.isEmpty else { return 0.0 }

        let total = Double(participants.count)

        // Count completed jobs; errors advance progress (your preference)
        let doneCount = participants.filter { $0.status == .done || $0.status == .error }.count

        // Include in-flight progress. If multiple encodes ever occur, we sum their fractions.
        let inFlightFracSum: Double = participants
            .filter { $0.status == .encoding }
            .compactMap { $0.progress }
            .map { max(0.0, min(1.0, $0)) }
            .reduce(0.0, +)

        // Cap just in case
        return max(0.0, min(1.0, (Double(doneCount) + inFlightFracSum) / total))
    }

    func progressOverlayLabel(files: [MediaItem], settings: Settings) -> String? {
        guard shouldShowFooterBatchProgress(files: files) else { return nil }
        let percent = Int((globalProgress(files: files) * 100).rounded())
        if let remaining = formatRemainingTime(files: files, settings: settings) {
            return "\(percent)% • \(remaining) left"
        }
        return "\(percent)%"
    }


    // MARK: - Message Logic

    func shouldShowMessages(_ messages: [AppLogEntry]) -> Bool {
        return messages.contains { !$0.acknowledged }
    }

    func unacknowledgedMessages(_ messages: [AppLogEntry]) -> [AppLogEntry] {
        return messages.filter { !$0.acknowledged }
    }

    func messageIcon(for level: LogLevel) -> String {
        switch level {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "exclamationmark.circle"
        }
    }

    func messageColor(for level: LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    // MARK: - Remaining Time (encoding + queued)
    // Keeping your existing function. If you see beachballs here later,
    // we can mirror the async pattern used above.
    func formatRemainingTime(files: [MediaItem], settings: Settings) -> String? {
        var totalRemaining: Double = 0
        var sawAny = false

        for item in files {
            // Skip items that aren't participating
            if item.status == .done || item.status == .error || item.status == .blocked {
                continue
            }
            // Only count queued items if the user has them checked
            if item.status == .queued && !item.isChecked {
                continue
            }

            guard let total = EncodeTimeEstimator.estimateSeconds(
                basics: nil,
                meta: item.meta,
                settings: settings,
                runMode: settings.runMode
            ), total.isFinite, total > 0 else {
                continue
            }

            let remaining: Double
            if item.status == .encoding, let p = item.progress, p.isFinite, p >= 0, p <= 1 {
                remaining = max(0, total * (1 - p))
            } else {
                // queued & checked (no progress yet) or encoding without progress -> assume full estimate
                remaining = total
            }

            totalRemaining += remaining
            sawAny = true
        }

        guard sawAny, totalRemaining > 0 else { return nil }
        return core.formatHMS(totalRemaining)
    }

    // MARK: - Utils

    private func formatFileSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        let units: [String] = ["B","KB","MB","GB","TB"]
        var value = Double(bytes)
        var idx = 0
        while value >= 1024.0 && idx < units.count - 1 {
            value /= 1024.0
            idx += 1
        }
        return String(format: "%.1f %@", value, units[idx])
    }
}

