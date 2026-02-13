// =============================
// File: EncodeTimeEstimator.swift
// =============================

import Foundation

struct EncodeTimeEstimator {

    /// Predict wall time in seconds for *local* encodes.
    /// Returns nil in Remote mode or if `basics` is not available yet.
    ///
    /// IMPORTANT: This estimator is pure (no probing, no AVFoundation, no I/O).
    /// Pass `basics` from your model/UI (e.g., RowProbeModel.basics / MediaProbeService cache).
    static func estimateSeconds(basics: MediaBasics?,
                                meta: MediaMetadata,
                                settings: Settings,
                                runMode: RunMode) -> Double? {
        // Do not estimate for remote jobs
        guard runMode == .localNative else { return nil }
        guard let b = basics else { return nil }

        // FPS: prefer metadata if present, else fall back to probed basics
        let fps: Double = {
            if let m = meta.nominalFPS, m.isFinite, m > 0 { return m }
            return b.fps
        }()

        // Duration: prefer metadata if present, else fall back to basics
        let dur: Double = {
            let d = meta.durationSeconds
            if d.isFinite, d > 0 { return d }
            return b.duration
        }()

        // Throughput (MP/s): try codec-aware first, then legacy, then heuristic
        let mpps =
            EncodeStatsStore.shared.averageMPps(runMode: "local",
                                                outW: b.outW, outH: b.outH,
                                                fps: fps, crf: settings.qualityCRF,
                                                codec: settings.codec, isHDR: nil)
            ?? EncodeStatsStore.shared.averageMPps(runMode: "local",
                                                   outW: b.outW, outH: b.outH,
                                                   fps: fps, crf: settings.qualityCRF)
            ?? defaultThroughputMPps(for: .localNative, outW: b.outW, outH: b.outH)

        // Mega-pixels to encode = (W*H*fps*duration)/1e6
        let mpTotal = Double(b.outW * b.outH) * fps * dur / 1_000_000.0
        guard mpTotal > 0, mpps > 0 else { return nil }

        return mpTotal / mpps
    }


    /// After a *local* encode finishes, call this to teach the estimator.
    /// IMPORTANT: This is also pure w.r.t. probing; pass `basics` captured earlier.
    static func recordCompleted(basics: MediaBasics?,
                                meta: MediaMetadata,
                                settings: Settings,
                                runMode: RunMode,
                                startedAt: Date,
                                finishedAt: Date) {
        // Only learn from Local runs
        guard runMode == .localNative else { return }

        let wall = max(0, finishedAt.timeIntervalSince(startedAt))
        guard wall > 0 else { return }

        // Need basics for consistent bucketing with estimateSeconds()
        guard let b = basics else { return }

        // FPS/duration selection matches estimateSeconds()
        let fps: Double = {
            if let m = meta.nominalFPS, m.isFinite, m > 0 { return m }
            return b.fps
        }()

        let dur: Double = {
            let d = meta.durationSeconds
            if d.isFinite, d > 0 { return d }
            return b.duration
        }()

        let sample = EncodeStatsStore.makeSample(
            runMode: "local",
            outW: b.outW, outH: b.outH,
            fps: fps,
            durationSec: dur,
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
        case .localNative:
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
