//
//  OutputEstimator.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/16/25.
//

import Foundation

struct OutputEstimator {

    /// Returns outW/outH, total_bps, estBytes, fps, secs
    /// IMPORTANT: This is a pure estimator (no probing, no AVFoundation, no I/O).
    /// Pass `basics` from your model/UI (e.g., RowProbeModel.basics / MediaProbeService cache).
    static func estimate(basics: MediaBasics?,
                         meta: MediaMetadata,
                         settings: Settings) -> (outW: Int, outH: Int, total_bps: Double, estBytes: Double, fps: Double, secs: Double)?
    {
        guard let b = basics else { return nil }

        // FPS: prefer metadata when present, else fall back to probed basics
        let fps: Double = {
            if let m = meta.nominalFPS, m.isFinite, m > 0 { return m }
            return b.fps
        }()

        // Duration: prefer metadata when present, else fall back to basics
        let secs: Double = {
            let d = meta.durationSeconds
            if d.isFinite, d > 0 { return d }
            return b.duration
        }()

        // Audio bitrate only if present
        let audio_bps = b.hasAudio ? 128_000.0 : 0.0

        // Learnable base bpppf (codec-aware first, fallback to legacy)
        let learned = EncodeStatsStore.shared.averageBpppf18(
            runMode: "local",
            outW: b.outW, outH: b.outH,
            fps: fps,
            crf: settings.qualityCRF,
            codec: settings.codec,
            isHDR: b.isHDR
        ) ?? EncodeStatsStore.shared.averageBpppf18(
            runMode: "local",
            outW: b.outW, outH: b.outH,
            fps: fps,
            crf: settings.qualityCRF,
            isHDR: b.isHDR
        )

        let fallbackBpppf18: Double = b.isHDR ? 0.10 : 0.07
        let baseBPPPF_CR18 = min(max(learned ?? fallbackBpppf18, 0.02), 0.25)

        // CRF scaling: lower CRF (better quality) = larger files
        let crf = settings.qualityCRF
        let scaleCRF = pow(1.11, Double(18 - crf)) // lower CRF => larger file
        let bpppf = baseBPPPF_CR18 * scaleCRF

        // Video bitrate (bits per pixel per frame * pixels * fps)
        let vpix = Double(b.outW * b.outH)
        let v_bps = bpppf * vpix * fps

        let total_bps = v_bps + audio_bps
        let estBytes  = total_bps * secs / 8.0

        return (b.outW, b.outH, total_bps, estBytes, fps, secs)
    }

    static func previewLine(basics: MediaBasics?,
                            meta: MediaMetadata,
                            settings: Settings,
                            nclcLabel: String?,
                            bullet: String = " • ") -> String? {
        guard let e = estimate(basics: basics, meta: meta, settings: settings) else { return nil }
        let mb = e.estBytes / (1024.0 * 1024.0)

        var parts: [String] = []
        parts.append("\(e.outW)×\(e.outH)")
        parts.append("\(Int(round(e.fps))) fps")
        parts.append("\(EncodeTimeEstimator.formatTime(e.secs))")
        if let lab = nclcLabel { parts.append(lab) }
        parts.append(String(format: "%.1f MB est.", mb))
        return parts.joined(separator: bullet)
    }
}
