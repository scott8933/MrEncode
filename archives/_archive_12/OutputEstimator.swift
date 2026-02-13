import Foundation
import AVFoundation

struct OutputEstimator {

    /// Core estimate used by the UI. Returns nil if it can’t read basic media info.
    static func estimate(url: URL,
                         meta: MediaMetadata,
                         settings: Settings) -> (outW: Int, outH: Int, total_bps: Double, estBytes: Double, fps: Double, secs: Double)? {

        let asset = AVAsset(url: url)

        // Video stream
        guard let vTrack = asset.tracks(withMediaType: .video).first else { return nil }

        // Source dims → scaled output dims
        let srcSize = vTrack.naturalSize.applying(vTrack.preferredTransform)
        let srcW = Int(abs(srcSize.width).rounded())
        let srcH = Int(abs(srcSize.height).rounded())
        guard srcW > 0, srcH > 0 else { return nil }

        let scale = settings.scale.factor
        let outW = max(1, Int(round(Double(srcW) * scale)))
        let outH = max(1, Int(round(Double(srcH) * scale)))

        // Timing
        let fps = meta.nominalFPS ?? (vTrack.nominalFrameRate > 0 ? Double(vTrack.nominalFrameRate) : 30.0)
        let secsRaw = meta.durationSeconds ?? CMTimeGetSeconds(asset.duration)
        guard secsRaw.isFinite, secsRaw > 0 else { return nil }
        let secs = secsRaw

        // Has audio? Only add audio bitrate if present.
        let hasAudio = !asset.tracks(withMediaType: .audio).isEmpty
        let audio_bps = hasAudio ? 128_000.0 : 0.0   // matches -b:a 128k in your builder

        // Rough video bitrate model (content-dependent; preview only).
        // Base at CRF 18; lower CRF => higher bitrate; higher CRF => lower bitrate.
        let crfClamped = max(0, min(51, settings.qualityCRF))
        let baseBPPPF_CR18: Double = 0.08
        // FIXED: correct direction — +6 CRF ≈ ½ bitrate; -6 CRF ≈ ×2 bitrate
        let crfFactor = pow(2.0, (18.0 - Double(crfClamped)) / 6.0)

        let video_bps = baseBPPPF_CR18 * Double(outW) * Double(outH) * fps * crfFactor

        let total_bps = max(0, video_bps) + audio_bps
        let estBytes = total_bps * secs / 8.0

        return (outW, outH, total_bps, estBytes, fps, secs)
    }

    /// Builds:  "Output: 1920×1080 • Rec.709 [1, 1, 1] • 12.3 Mbps • (est.) 1.25 GB"
    static func previewLine(url: URL,
                            meta: MediaMetadata,
                            settings: Settings,
                            nclcLabel: String?,
                            bullet: String = " • ") -> String? {
        guard let e = estimate(url: url, meta: meta, settings: settings) else { return nil }
        let dimsStr = "\(e.outW)×\(e.outH)"
        let bitrateStr = formatBitrate(e.total_bps)
        let sizeStr = formatFileSize(Int64(e.estBytes.rounded()))
        let parts = ["Output: \(dimsStr)",
                     nclcLabel ?? "",
                     bitrateStr,
                     "(est.) \(sizeStr)"].filter { !$0.isEmpty }
        return parts.joined(separator: bullet)
    }

    // MARK: - Local formatters (standalone)

    private static func formatFileSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000.0
        if gb >= 1.0 { return String(format: "%.2f GB", gb) }
        let mb = Double(bytes) / 1_000_000.0
        if mb >= 100 { return String(format: "%.0f MB", mb) }
        if mb >= 10  { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f MB", mb)
    }

    private static func formatBitrate(_ bps: Double) -> String {
        let mbps = bps / 1_000_000.0
        if mbps >= 1000.0 { return String(format: "%.1f Gbps", mbps / 1000.0) }
        if mbps >= 100.0  { return String(format: "%.0f Mbps", mbps) }
        return String(format: "%.1f Mbps", mbps)
    }
}
