// =============================
// File: EncodeTimeEstimator.swift
// =============================
import Foundation
import AVFoundation

struct EncodeTimeEstimator {

    /// Predict wall time in seconds for *local* encodes.
    /// Returns nil in Remote mode or if media info can’t be read.
    static func estimateSeconds(url: URL,
                                meta: MediaMetadata,
                                settings: Settings,
                                runMode: RunMode) -> Double? {
        // Do not estimate for remote jobs
        guard runMode == .localFFmpeg else { return nil }

        // Probe once (dims / fps / duration / audio / hdr)
        guard let b = MediaProbe.readBasics(url: url, meta: meta, scale: settings.scale) else { return nil }

        // Throughput (MP/s): try codec-aware first, then legacy, then heuristic
        let mpps =
            EncodeStatsStore.shared.averageMPps(runMode: "local",
                                                outW: b.outW, outH: b.outH,
                                                fps: b.fps, crf: settings.qualityCRF,
                                                codec: settings.codec, isHDR: nil)
            ?? EncodeStatsStore.shared.averageMPps(runMode: "local",
                                                   outW: b.outW, outH: b.outH,
                                                   fps: b.fps, crf: settings.qualityCRF)
            ?? defaultThroughputMPps(for: .localFFmpeg, outW: b.outW, outH: b.outH)

        // Mega-pixels to encode = (W*H*fps*duration)/1e6
        let mpTotal = Double(b.outW * b.outH) * b.fps * b.duration / 1_000_000.0
        guard mpTotal > 0, mpps > 0 else { return nil }

        return mpTotal / mpps
    }


    /// After a *local* encode finishes, call this to teach the estimator.
    static func recordCompleted(url: URL,
                                meta: MediaMetadata,
                                settings: Settings,
                                runMode: RunMode,
                                startedAt: Date,
                                finishedAt: Date) {
        // Only learn from Local runs
        guard runMode == .localFFmpeg else { return }

        let wall = max(0, finishedAt.timeIntervalSince(startedAt))
        guard wall > 0 else { return }

        // Probe once for consistent bucketing with estimateSeconds()
        guard let b = MediaProbe.readBasics(url: url, meta: meta, scale: settings.scale) else { return }

        let sample = EncodeStatsStore.makeSample(
            runMode: "local",
            outW: b.outW, outH: b.outH,
            fps: b.fps,
            durationSec: b.duration,
            wallTimeSec: wall,
            crf: settings.qualityCRF
        )

        // Teach codec-aware buckets (falls back automatically at read time if empty)
        EncodeStatsStore.shared.record(sample: sample, codec: settings.codec)
    }


    // MARK: - Fallback heuristics

    /// Conservative defaults until the model learns (mega-pixels/sec).
    private static func defaultThroughputMPps(for runMode: RunMode, outW: Int, outH: Int) -> Double {
        let long = max(outW, outH)
        switch runMode {
        case .localFFmpeg:
            // Keep it simple: smaller frames are faster. Tune later if needed.
            return (long >= 3840) ? 12 : 18   // 4K-ish: 12 MP/s, ≤1080/1440p-ish: 18 MP/s
        case .remoteDeadline:
            // Not used (we don't estimate remote), but leave a reasonable number.
            return (long >= 3840) ? 25 : 30
        }
    }

    // MARK: - UI helper

    /// Short human-readable time string.
    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "–" }
        if seconds < 1 { return String(format: "%.1fs", seconds) }
        if seconds < 90 { return String(format: "%.0fs", seconds) }
        let m = Int(seconds / 60.0)
        let s = Int(seconds.truncatingRemainder(dividingBy: 60.0))
        if m < 60 { return String(format: "%dm %02ds", m, s) }
        let h = m / 60
        let mm = m % 60
        return String(format: "%dh %02dm", h, mm)
    }
}
