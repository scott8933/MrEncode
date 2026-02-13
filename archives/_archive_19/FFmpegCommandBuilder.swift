// =============================
// File: FFmpegCommandBuilder.swift
// =============================
import Foundation
import AVFoundation

enum FFmpegCommandBuilder {

    // MARK: - Public

    static func buildArgs(item: MediaItem, output: URL, settings: Settings) -> [String] {
        buildArgs(input: item.url, output: output, settings: settings, meta: item.meta)
    }

    static func buildArgs(input: URL, output: URL, settings: Settings) -> [String] {
        buildArgs(input: input, output: output, settings: settings, meta: .empty)
    }

    // MARK: - Core

    private static func buildArgs(input: URL,
                                  output: URL,
                                  settings: Settings,
                                  meta: MediaMetadata) -> [String] {
        var args: [String] = []

        // Quiet & overwrite
        args += ["-hide_banner", "-y"]

        // Input
        args += ["-i", input.path]

        // Video encoder (10-bit HEVC, main10)
        args += ["-c:v", "libx265",
                 "-pix_fmt", "yuv420p10le",
                 "-profile:v", "main10",
                 "-crf", String(settings.qualityCRF),
                 "-preset", "fast"]

        // Build filter chain
        var filters: [String] = []
        if let s = scaleFilter(for: settings.scale) { filters.append(s) }
        if let overlay = overlayFilters(input: input, meta: meta, settings: settings), !overlay.isEmpty {
            filters.append(contentsOf: overlay)
        }
        if !filters.isEmpty {
            args += ["-vf", filters.joined(separator: ",")]
        }

        // Audio — probe, don’t assume
        if let basics = MediaProbe.readBasics(url: input, meta: meta, scale: settings.scale), basics.hasAudio {
            args += ["-c:a", "aac", "-b:a", "128k"]
        } else {
            args += ["-an"]
        }

        // Apple playback tag
        args += ["-tag:v", "hvc1"]

        // === NCLC tagging ===
        // If Settings say "No Change": pass through input tags if present.
        // Else if a specific tag is chosen: write those tags explicitly.
        if let trip = tripletToApply(from: settings, meta: meta) {
            args += ["-color_primaries", trip.primaries,
                     "-color_trc",       trip.trc,
                     "-colorspace",      trip.matrix]
        }

        // Output
        args.append(output.path)
        return args
    }

    // MARK: - Scaling / evenizing

    /// Always evenize + square pixels to keep libx265 happy.
    private static func scaleFilter(for scale: ScaleOption) -> String? {
        switch scale {
        case .oneToOne: return #"scale=ceil(iw/2)*2:ceil(ih/2)*2,setsar=1"#
        case .half:     return #"scale=ceil(iw*0.5/2)*2:ceil(ih*0.5/2)*2,setsar=1"#
        case .quarter:  return #"scale=ceil(iw*0.25/2)*2:ceil(ih*0.25/2)*2,setsar=1"#
        }
    }

    // MARK: - Overlays (timecode / frame / filename)

    /// Uses metadata fps & start timecode precisely; groups by corner & stacks lines to avoid overlap.
    /// Derives margin/gap/box padding from the **final output size** so scale is respected.
    private static func overlayFilters(input: URL,
                                       meta: MediaMetadata,
                                       settings: Settings) -> [String]? {
        // Quick exit if user disabled everything
        let wantTC   = settings.burnInTimecode
        let wantFr   = settings.burnInFrames
        let wantName = settings.burnInFilename
        guard wantTC || wantFr || wantName else { return nil }

        // Probe final render characteristics (post-scale)
        guard let basics = MediaProbe.readBasics(url: input, meta: meta, scale: settings.scale) else { return nil }
        let outW = basics.outW, outH = basics.outH
        // fps: prefer exiftool (meta.nominalFPS) when available
        let fps = meta.nominalFPS ?? basics.fps

        // Font sizing (responsive to output size)
        let font = fontBlock(outW: outW, outH: outH)

        // Layout metrics derived from output size / font (scale-aware)
        let metrics = overlayMetrics(outW: outW, outH: outH, fontSize: font.fontsize)

        // Colors (text + boxed background) — box padding scales with font size
        let color = colorBlock(textHex: settings.overlayTextColorHex,
                               textAlpha: settings.overlayTextColorAlpha,
                               boxHex: settings.overlayBoxColorHex,
                               boxAlpha: settings.overlayBoxColorAlpha,
                               pad: metrics.boxPad)

        // Prepare overlay "requests" (we will group & stack them per position)
        struct Request { let position: BurnInPosition; let payload: String }
        var reqs: [Request] = []

        // 1) TIMECODE — drawtext native timecode with accurate start + rate
        if wantTC {
            let pos = settings.burnInTimecodePosition
            let (tcText, rateOpt) = timecodeDrawtextOptions(meta: meta, fps: fps)
            let payload = "timecode='\(tcText)':\(rateOpt):tc24hmax=1"
            reqs.append(.init(position: pos, payload: payload))
        }

        // 2) FRAMES — exact frame number with correct start-offset derived from start timecode
        if wantFr {
            let pos = settings.burnInFramesPosition
            let startFrame = startFrameFromMetadata(meta: meta, fps: fps)
            let payload = "text='Frame\\: %{eif\\:n+\(startFrame)\\:d}'"
            reqs.append(.init(position: pos, payload: payload))
        }

        // 3) FILENAME — sanitized for drawtext
        if wantName {
            let pos = settings.burnInFilenamePosition
            let escaped = escapeForDrawtext(input.lastPathComponent)
            let payload = "text='\(escaped)'"
            reqs.append(.init(position: pos, payload: payload))
        }

        // Group by position and build stacked drawtext filters (no overlap)
        var filters: [String] = []
        let grouped = Dictionary(grouping: reqs, by: { $0.position })
        for (pos, group) in grouped {
            for (idx, req) in group.enumerated() {
                let f = drawtextCore(payload: req.payload,
                                     font: font,
                                     color: color,
                                     position: pos,
                                     indexInStack: idx,
                                     countInStack: group.count,
                                     metrics: metrics)
                filters.append(f)
            }
        }
        return filters
    }

    // MARK: Overlay: helpers

    /// Derive scale-aware layout values from output size & font size.
    private static func overlayMetrics(outW: Int, outH: Int, fontSize: Int)
        -> (margin: Int, gap: Int, boxPad: Int)
    {
        // Margin ~1.2% of height (min 8, max 48)
        let margin = max(8, min(48, Int(round(Double(outH) * 0.012))))
        // Gap ~25% of font size (min 2, max 24)
        let gap    = max(2, min(24, Int(round(Double(fontSize) * 0.25))))
        // Box border width (“padding”) ~ fontSize/6 (min 2, max 16)
        let boxPad = max(2, min(16, Int(round(Double(fontSize) / 6.0))))
        return (margin, gap, boxPad)
    }

    /// Drawtext core builder: merges supplied `payload` (text=... or timecode=...)
    /// with font/color and absolute positioning. Handles stacking math so overlays never overlap.
    private static func drawtextCore(payload: String,
                                     font: (fontfile: String, fontsize: Int),
                                     color: (fontcolor: String, box: (enabled: Bool, spec: String)),
                                     position: BurnInPosition,
                                     indexInStack: Int,
                                     countInStack: Int,
                                     metrics: (margin: Int, gap: Int, boxPad: Int)) -> String {
        var parts: [String] = []

        if !font.fontfile.isEmpty { parts.append("fontfile='\(font.fontfile)'") }
        parts.append("fontsize=\(font.fontsize)")
        parts.append("fontcolor=\(color.fontcolor)")
        if color.box.enabled { parts.append(color.box.spec) }

        let (xExpr, yExpr) = stackedXY(for: position,
                                       idx: indexInStack,
                                       count: countInStack,
                                       margin: metrics.margin,
                                       gap: metrics.gap)
        parts.append("x=\(xExpr)")
        parts.append("y=\(yExpr)")

        parts.append(payload)
        return "drawtext=" + parts.joined(separator: ":")
    }

    /// Deterministic stacking per corner (no overlap). Uses text height `th` from drawtext.
    /// Top corners stack downward (+), bottom corners stack upward (−).
    /// Middle corners also stack downward (simple & readable).
    private static func stackedXY(for position: BurnInPosition,
                                  idx: Int,
                                  count: Int,
                                  margin: Int,
                                  gap: Int) -> (x: String, y: String) {
        let lineStep = "(th+\(gap))"

        // Y expressions per vertical anchor
        let topY    = "\(margin) + \(idx)*\(lineStep)"
        let midY    = "(h-th)/2 + \(idx)*\(lineStep)"
        let botY    = "h-th-\(margin) - \(idx)*\(lineStep)"

        // X expressions per horizontal anchor
        let leftX   = "\(margin)"
        let midX    = "(w-tw)/2"
        let rightX  = "w-tw-\(margin)"

        switch position {
        case .upperLeft:    return (leftX,  topY)
        case .upperCenter:  return (midX,   topY)
        case .upperRight:   return (rightX, topY)
        case .middleLeft:   return (leftX,  midY)
        case .middleRight:  return (rightX, midY)
        case .lowerLeft:    return (leftX,  botY)
        case .lowerCenter:  return (midX,   botY)
        case .lowerRight:   return (rightX, botY)
        }
    }

    /// Font choice and size (responsive but conservative)
    private static func fontBlock(outW: Int, outH: Int) -> (fontfile: String, fontsize: Int) {
        let menlo = "/System/Library/Fonts/Menlo.ttc"
        let fontfile = FileManager.default.fileExists(atPath: menlo) ? menlo : ""
        let shortSide = min(outW, outH)
        let size = max(18, min(64, Int(round(Double(shortSide) * 0.035))))
        return (fontfile, size)
    }

    /// Colors for drawtext label + boxed background; box padding scales with font size.
    private static func colorBlock(textHex: String,
                                   textAlpha: Double,
                                   boxHex: String,
                                   boxAlpha: Double,
                                   pad: Int) -> (fontcolor: String, box: (enabled: Bool, spec: String)) {
        let fontcolor = ffColor(hex: textHex, alpha: textAlpha)
        let boxcolor  = ffColor(hex: boxHex, alpha: boxAlpha)
        let boxEnabled = boxAlpha > 0.001
        let spec = "box=1:boxcolor=\(boxcolor):boxborderw=\(pad)"
        return (fontcolor, (boxEnabled, spec))
    }

    /// Convert "#RRGGBB" or "RRGGBB" + alpha (0..1) to ffmpeg "0xRRGGBB@alpha".
    private static func ffColor(hex: String, alpha: Double) -> String {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let rgb = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let safe = rgb.count == 6 ? rgb : "FFFFFF"
        let a = max(0.0, min(1.0, alpha))
        return "0x\(safe.uppercased())@\(String(format: "%.3f", a))"
    }

    /// Escape for drawtext single-quoted context.
    private static func escapeForDrawtext(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: ":", with: "\\:")
         .replacingOccurrences(of: "'", with: "\\'")
    }

    // MARK: Accurate Timecode / Frame math

    /// Build `timecode=` payload using accurate start and rate from metadata.
    /// - Uses `meta.startTimecode` if present, else "00:00:00:00".
    /// - Uses nominal FPS from exiftool if present, else probed fps.
    /// - Uses drop-frame if fps ≈ 29.97 or 59.94 (common practice).
    private static func timecodeDrawtextOptions(meta: MediaMetadata, fps: Double) -> (tcStartEscaped: String, rateOption: String) {
        let tcStart = (meta.startTimecode?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { !$0.isEmpty ? $0 : nil } ?? "00:00:00:00"
        let tcEscaped = escapeForDrawtext(tcStart)
        let rate = fpsRatioString(fps)  // e.g., "30000/1001" for 29.97
        // drawtext uses "timecode_rate=", not "r="
        return (tcEscaped, "timecode_rate=\(rate)")
    }

    /// Start frame offset from metadata start timecode (returns 0 if unknown).
    /// Handles drop-frame when fps ≈ 29.97/59.94; otherwise straight HH:MM:SS:FF math.
    private static func startFrameFromMetadata(meta: MediaMetadata, fps: Double) -> Int {
        guard let tc = meta.startTimecode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tc.isEmpty else { return 0 }

        // Parse HH:MM:SS:FF (accept ';' or ':' between SS and FF)
        let cleaned = tc.replacingOccurrences(of: ";", with: ":")
        let parts = cleaned.split(separator: ":").map { String($0) }
        guard parts.count == 4,
              let hh = Int(parts[0]),
              let mm = Int(parts[1]),
              let ss = Int(parts[2]),
              let ff = Int(parts[3]) else { return 0 }

        let isDrop = abs(fps - 29.97) < 0.01 || abs(fps - 59.94) < 0.01
        if !isDrop {
            // Non-drop: straightforward
            let framesPerSec = Int(round(fps))
            return ((hh * 3600) + (mm * 60) + ss) * framesPerSec + ff
        } else {
            // Drop-frame (SMPTE): drop 2 frames/minute (or 4 at 59.94), except every 10th minute
            let framesPerSec = (abs(fps - 59.94) < 0.01) ? 60 : 30
            let dropsPerMin  = (framesPerSec == 60) ? 4 : 2

            let totalMinutes = hh * 60 + mm
            let dropped = dropsPerMin * (totalMinutes - totalMinutes / 10)
            let baseFrames = ((hh * 3600) + (mm * 60) + ss) * framesPerSec + ff
            return baseFrames - dropped
        }
    }

    /// Convert fps to a rational string for ffmpeg (timecode_rate).
    private static func fpsRatioString(_ fps: Double) -> String {
        let table: [(Double, String)] = [
            (23.976, "24000/1001"),
            (29.97,  "30000/1001"),
            (59.94,  "60000/1001")
        ]
        for (t, r) in table where abs(fps - t) < 0.01 { return r }
        let ints: [Double] = [24, 25, 30, 50, 60, 120]
        for v in ints where abs(fps - v) < 0.01 { return "\(Int(v))/1" }
        // Fallback: nearest integer
        return "\(Int(round(fps)))/1"
    }

    // MARK: - NCLC "No Change" passthrough

    /// Decide which NCLC triplet to write:
    /// - "No Change": use input meta if available (pass-through).
    /// - Specific tag: use table lookup.
    /// - Otherwise: nil (write nothing).
    private static func tripletToApply(from settings: Settings, meta: MediaMetadata) -> NCLCMap.Triplet? {
        let tag = settings.nclcTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if tag == "no change" || tag == "no-change" || tag == "nochange" {
            if let p = meta.colorPrimaries,
               let t = meta.transferFunction,
               let m = meta.ycbcrMatrix {
                return .init(primaries: p, trc: t, matrix: m)
            }
            return nil
        }
        return NCLCMap.lookup(labelOrCode: settings.nclcTag)
    }
}
