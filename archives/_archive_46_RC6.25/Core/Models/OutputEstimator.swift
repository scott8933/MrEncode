import Foundation
import AVFoundation

struct OutputEstimator {

    /// Returns outW/outH, total_bps, estBytes, fps, secs
    static func estimate(url: URL,
                         meta: MediaMetadata,
                         settings: Settings) -> (outW: Int, outH: Int, total_bps: Double, estBytes: Double, fps: Double, secs: Double)?
    {
        guard let b = MediaProbe.readBasics(url: url, meta: meta, scale: settings.scale) else { return nil }

        // Audio bitrate only if present
        let audio_bps = b.hasAudio ? 128_000.0 : 0.0

        // Learnable base bpppf (codec-aware first, fallback to legacy)
        let learned = EncodeStatsStore.shared.averageBpppf18(
            runMode: "local",
            outW: b.outW, outH: b.outH,
            fps: b.fps,
            crf: settings.qualityCRF,
            codec: settings.codec,
            isHDR: b.isHDR
        ) ?? EncodeStatsStore.shared.averageBpppf18(
            runMode: "local",
            outW: b.outW, outH: b.outH,
            fps: b.fps,
            crf: settings.qualityCRF,
            isHDR: b.isHDR
        )

        let fallbackBpppf18: Double = b.isHDR ? 0.10 : 0.07
        let baseBPPPF_CR18 = min(max(learned ?? fallbackBpppf18, 0.02), 0.25)

        // CRF scaling: FIXED - lower CRF (better quality) = larger files
        let crf = settings.qualityCRF
        let scaleCRF = pow(1.11, Double(18 - crf)) // lower CRF => larger file
        let bpppf = baseBPPPF_CR18 * scaleCRF

        // Video bitrate (bits per pixel per frame * pixels * fps)
        let vpix = Double(b.outW * b.outH)
        let v_bps = bpppf * vpix * b.fps

        let total_bps = v_bps + audio_bps
        let estBytes  = total_bps * b.duration / 8.0

        return (b.outW, b.outH, total_bps, estBytes, b.fps, b.duration)
    }

    static func previewLine(url: URL,
                            meta: MediaMetadata,
                            settings: Settings,
                            nclcLabel: String?,
                            bullet: String = " • ") -> String? {
        guard let e = estimate(url: url, meta: meta, settings: settings) else { return nil }
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
