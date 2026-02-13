// =============================
// File: MetadataExtractor.swift
// =============================

import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

/// Extracts per-file technical metadata for overlays and color tagging.
/// Native-only: AVFoundation/CoreMedia. No external tool fallback.
enum MetadataExtractor {

    static func extract(url: URL) -> MediaMetadata {
        extract(for: url)
    }

    /// Extract NCLC (primaries/trc/matrix), nominal FPS, and start timecode if present.
    /// Synchronous: AVFoundation only.
    /// Cancellation: returns partial results early if the enclosing Task is cancelled.
    static func extract(for url: URL) -> MediaMetadata {
        var out = MediaMetadata.empty
        if Task.isCancelled { return out }

        let asset = AVAsset(url: url)

        // Duration from AVFoundation (synchronous)
        let d = asset.duration
        if d.isValid, d.timescale != 0, d.value != 0 {
            out.durationSeconds = Double(d.value) / Double(d.timescale)
        }
        if Task.isCancelled { return out }

        // ---- Video track → FPS + NCLC --------------------------------------
        if let vTrack = asset.tracks(withMediaType: .video).first {

            // FPS (prefer minFrameDuration → accurate and non-deprecated)
            if vTrack.minFrameDuration.isValid,
               vTrack.minFrameDuration.timescale != 0,
               vTrack.minFrameDuration.value != 0 {
                let mfd = vTrack.minFrameDuration
                out.nominalFPS = Double(mfd.timescale) / Double(mfd.value)
            } else {
                let nominal = vTrack.nominalFrameRate
                if nominal > 0 {
                    out.nominalFPS = Double(nominal)
                }
            }

            if Task.isCancelled { return out }

            // NCLC from CMFormatDescription extensions
            if let firstAny = vTrack.formatDescriptions.first {
                let cf = firstAny as CFTypeRef
                if CFGetTypeID(cf) == CMFormatDescriptionGetTypeID() {
                    let fmt = cf as! CMFormatDescription
                    if let ext = CMFormatDescriptionGetExtensions(fmt) as? [String: Any] {

                        if let prim = (ext[kCVImageBufferColorPrimariesKey as String] ??
                                       ext["CVImageBufferColorPrimaries"]) as? String {
                            // Map AVFoundation name → numeric code string when possible
                            out.colorPrimaries = mapNCLCCode(prim, kind: .primaries) ?? prim
                        }

                        if let trc = (ext[kCVImageBufferTransferFunctionKey as String] ??
                                      ext["CVImageBufferTransferFunction"]) as? String {
                            out.transferFunction = mapNCLCCode(trc, kind: .transfer) ?? trc
                        }

                        if let mat = (ext[kCVImageBufferYCbCrMatrixKey as String] ??
                                      ext["CVImageBufferYCbCrMatrix"]) as? String {
                            out.ycbcrMatrix = mapNCLCCode(mat, kind: .matrix) ?? mat
                        }
                    }
                }
            }
        }
        if Task.isCancelled { return out }

        // ---- Attempt to get start TC (best-effort) --------------------------
        // Policy: If we can't confidently find it via AVFoundation metadata, we leave it nil.
        if out.startTimecode == nil, let tc = quickTimeStartTimecode(from: asset) {
            out.startTimecode = tc
        }

        #if DEBUG
        if let p = out.colorPrimaries, let t = out.transferFunction, let m = out.ycbcrMatrix {
            print("MetadataExtractor NCLC: [\(p), \(t), \(m)] for \(url.lastPathComponent)")
        }
        #endif

        return out
    }

    // MARK: - QuickTime metadata → start timecode

    /// Attempt to find a plausible timecode string in the asset's metadata.
    private static func quickTimeStartTimecode(from asset: AVAsset) -> String? {
        for fmt in asset.availableMetadataFormats {
            let items = asset.metadata(forFormat: fmt)

            // 1) Look for identifiers that contain 'timecode'
            if let item = items.first(where: { ($0.identifier?.rawValue.lowercased().contains("timecode") ?? false) }),
               let v = item.stringValue, isLikelyTimecode(v) {
                return normalizeTCString(v)
            }

            // 2) Fallback: inspect keys/titles (light heuristic)
            for item in items {
                let keyLower = (item.key as? String)?.lowercased() ?? ""
                let keySpace = item.keySpace?.rawValue.lowercased() ?? ""
                if (keyLower.contains("timecode") || keySpace.contains("timecode")),
                   let v = item.stringValue, isLikelyTimecode(v) {
                    return normalizeTCString(v)
                }
            }
        }
        return nil
    }

    /// Very loose check for HH:MM:SS:FF or HH:MM:SS;FF
    private static func isLikelyTimecode(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^\d{2}:\d{2}:\d{2}[:;]\d{2}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private static func normalizeTCString(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
         .replacingOccurrences(of: ".", with: ":")
    }

    // MARK: - NCLC normalization & mapping

    private enum NCLCKind { case primaries, transfer, matrix }

    /// Return a canonical nclc code **as a String** ("1", "13", "1") when we can infer it.
    /// Accepts plain numbers ("13") or common names ("BT.709", "ITU_R_709_2", "sRGB", "HLG", etc).
    private static func mapNCLCCode(_ raw: String, kind: NCLCKind) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int(trimmed) { return String(n) }  // already numeric

        let s = trimmed
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")

        switch kind {
        case .primaries:
            // 1 = BT.709
            if s.contains("bt709") || s.contains("itur709") || s.contains("iturbt709") { return "1" }
            // 9 = BT.2020
            if s.contains("bt2020") || s.contains("itur2020") || s.contains("iturbt2020") { return "9" }
            // 12 = P3 D65
            if s.contains("p3d65") || s.contains("displayp3") || s == "p3" { return "12" }
            // 5 = BT.470BG (PAL/SECAM 601)
            if s.contains("bt470bg") || s.contains("pal") { return "5" }
            // 6 = SMPTE 170M (NTSC 601) / SMPTE-C
            if s.contains("smpte170m") || s.contains("smptec") || s.contains("ntsc") || s.contains("bt601") { return "6" }
            return nil

        case .transfer:
            // 1 = BT.709 OETF
            if s.contains("bt709") || s.contains("itur709") || s.contains("iturbt709") { return "1" }
            // 13 = sRGB (IEC 61966-2-1)
            if s.contains("iec6196621") || s.contains("srgb") { return "13" }
            // 16 = PQ (SMPTE ST 2084 / ITU-R BT.2100 PQ)
            if s.contains("smpte2084") || s.contains("st2084") || s.contains("pq") || s.contains("bt2100pq") { return "16" }
            // 18 = HLG (ARIB STD-B67 / ITU-R BT.2100 HLG)
            if s.contains("aribstdb67") || s.contains("hlg") || s.contains("bt2100hlg") { return "18" }
            // 4 = gamma 2.2
            if s.contains("gamma22") || s == "g22" { return "4" }
            // 5 = gamma 2.8
            if s.contains("gamma28") || s == "g28" { return "5" }
            return nil

        case .matrix:
            // 1 = BT.709
            if s.contains("bt709") || s.contains("itur709") || s.contains("iturbt709") { return "1" }
            // 9 = BT.2020 non-constant luminance (most common)
            if s.contains("bt2020") || s.contains("itur2020") || s.contains("iturbt2020") { return "9" }
            // 5 = BT.470BG (PAL 601)
            if s.contains("bt470bg") || s.contains("pal") { return "5" }
            // 6 = SMPTE 170M / BT.601 (NTSC 601)
            if s.contains("smpte170m") || s.contains("bt601") || s.contains("601") || s.contains("ntsc") { return "6" }
            return nil
        }
    }
}
