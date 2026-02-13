// =============================
// File: FFmpegCommandBuilder.swift
// =============================


import Foundation

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

        // Determine pixel changes
        let wantsScale   = settings.scale != .oneToOne
        let wantsOverlay = settings.burnInFrames || settings.burnInTimecode || settings.burnInFilename

        // Get container format from output extension
        let containerFormat = settings.containerFormat

        // =========================
        // BYPASS (No Recompression) BEHAVIOR
        // =========================
        if settings.codec == .bypass {
            if !wantsScale && !wantsOverlay {
                // Pure passthrough: stream copy; optionally write container-level color tags
                args += ["-map", "0", "-c", "copy"]

                if let trip = tripletToApply(from: settings, meta: meta) {
                    // Container-specific color tagging
                    addColorTagging(&args, triplet: trip, container: containerFormat)
                }

                // Keep original codec tag (no override)
                args.append(output.path)
                return args
            } else {
                // Pixel changes needed → re-encode with the ORIGINAL codec (stay in same family)
                // Build filters (scale + overlays)
                var filters: [String] = []
                if let s = scaleFilter(settings: settings) { filters.append(s) }
                if let overlay = overlayFilters(input: input, meta: meta, settings: settings),
                   !overlay.isEmpty {
                    filters.append(contentsOf: overlay)
                }
                if !filters.isEmpty { args += ["-vf", filters.joined(separator: ",")] }

                // Pixel changes requested while in bypass mode.
                // We cannot "stay in the same family" without probing; use a safe intra codec.
                args += ["-c:v", "prores_ks", "-profile:v", "3"]   // ProRes 422 HQ

                // Audio
                args += ["-map", "0:v:0", "-map", "0:a?"]
                args += ["-c:a", "aac", "-b:a", "128k"]


                // >>> Preserve VFR
                applyVFRPassThrough(&args, outputExt: output.pathExtension.lowercased())

                // Container-level NCLC (optional)
                if let trip = tripletToApply(from: settings, meta: meta) {
                    addColorTagging(&args, triplet: trip, container: containerFormat)
                }

                // Keep original codec tag (no explicit override)
                args.append(output.path)
                return args
            }
        }

        // =========================
        // NORMAL PATH (Recompress) — select H.264 or HEVC based on Settings
        // =========================

        // Video encoder selection
        switch settings.codec {
        case .h264:
            // H.264 delivery (8-bit typical)
            args += ["-c:v", "libx264",
                     "-crf", String(settings.qualityCRF),
                     "-preset", "medium",
                     "-pix_fmt", "yuv420p"]
        case .hevc:
            // HEVC delivery (10-bit main10 as your current default)
            args += ["-c:v", "libx265",
                     "-pix_fmt", "yuv420p10le",
                     "-profile:v", "main10",
                     "-crf", String(settings.qualityCRF),
                     "-preset", "medium"]
        case .bypass:
            // Already handled above; keep the compiler happy.
            break
        }

        // Build filter chain
        var filters: [String] = []
        if let s = scaleFilter(settings: settings) { filters.append(s) }
        if let overlay = overlayFilters(input: input, meta: meta, settings: settings), !overlay.isEmpty {
            filters.append(contentsOf: overlay)
        }
        if !filters.isEmpty {
            args += ["-vf", filters.joined(separator: ",")]
        }

        // Audio — do not pre-probe. Map optional audio and encode if present.
        args += ["-map", "0:v:0", "-map", "0:a?"]
        args += ["-c:a", "aac", "-b:a", "128k"]
        
        // >>> Preserve VFR
        applyVFRPassThrough(&args, outputExt: output.pathExtension.lowercased())

        // Container-specific codec tagging (now depends on chosen codec)
        addCodecTagging(&args, codec: settings.codec, container: containerFormat)

        // === NCLC tagging ===
        // If Settings say "No Change": pass through input tags if present.
        // Else if a specific tag is chosen: write those tags explicitly.
        if let trip = tripletToApply(from: settings, meta: meta) {
            addColorTagging(&args, triplet: trip, container: containerFormat)
        }

        // Output
        args.append(output.path)
        return args
    }


        // MARK: - Container-specific helpers

        /// Add color tagging arguments based on container format
        private static func addColorTagging(_ args: inout [String], triplet: NCLCMap.Triplet, container: ContainerFormat) {
            switch container {
            case .mov:
                // MOV-specific color tagging
                args += ["-movflags", "write_colr",
                         "-color_primaries", triplet.primaries,
                         "-color_trc",       triplet.trc,
                         "-colorspace",      triplet.matrix]
            case .mp4:
                // MP4 color tagging (no movflags needed)
                args += ["-color_primaries", triplet.primaries,
                         "-color_trc",       triplet.trc,
                         "-colorspace",      triplet.matrix]
            }
        }

    /// Add codec tagging based on chosen codec + container
    private static func addCodecTagging(_ args: inout [String],
                                        codec: VideoCodec,
                                        container: ContainerFormat) {
        switch codec {
        case .h264:
            // H.264 FourCC across MOV/MP4
            args += ["-tag:v", "avc1"]
        case .hevc:
            // HEVC tag varies by container
            let tag = (container == .mov) ? "hvc1" : "hev1"
            args += ["-tag:v", tag]
        case .bypass:
            // When bypassing, we don't override source codec tags
            break
        }
    }


    // MARK: - Scaling / evenizing (preset + custom)

    /// Settings-aware scaling:
    /// - Presets: oneToOne / half / quarter
    /// - Custom: stretch / fit (pad) / fill (crop), with anchor + center override
    private static func scaleFilter(settings: Settings) -> String? {

        // Presets (existing behavior)
        if settings.scale != .custom {
            return scaleFilter(for: settings.scale)
        }

        // Custom
        let w = evenize(max(2, settings.customScaleWidth))
        let h = evenize(max(2, settings.customScaleHeight))

        switch settings.customScaleMode {

        case .stretch:
            // Force exact size (AR ignored)
            return "scale=\(w):\(h),setsar=1"

        case .fit:
            // Preserve AR, fit inside, then pad to exact size
            let xy = padXY(center: settings.customScaleAnchorCenter,
                           anchor: settings.customScaleAnchor)
            return "scale=w=\(w):h=\(h):force_original_aspect_ratio=decrease," +
                   "pad=\(w):\(h):\(xy),setsar=1"

        case .fill:
            // Preserve AR, fill, then crop to exact size
            let xy = cropXY(center: settings.customScaleAnchorCenter,
                            anchor: settings.customScaleAnchor)
            return "scale=w=\(w):h=\(h):force_original_aspect_ratio=increase," +
                   "crop=\(w):\(h):\(xy),setsar=1"
        }
    }

    private static func evenize(_ v: Int) -> Int {
        (v / 2) * 2
    }

    /// pad x:y expressions use ow/oh vs iw/ih
    private static func padXY(center: Bool, anchor: BurnInPosition) -> String {
        if center { return "x=(ow-iw)/2:y=(oh-ih)/2" }

        switch anchor {
        case .upperLeft:   return "x=0:y=0"
        case .upperCenter: return "x=(ow-iw)/2:y=0"
        case .upperRight:  return "x=ow-iw:y=0"

        case .middleLeft:  return "x=0:y=(oh-ih)/2"
        case .center:      return "x=(ow-iw)/2:y=(oh-ih)/2"
        case .middleRight: return "x=ow-iw:y=(oh-ih)/2"

        case .lowerLeft:   return "x=0:y=oh-ih"
        case .lowerCenter: return "x=(ow-iw)/2:y=oh-ih"
        case .lowerRight:  return "x=ow-iw:y=oh-ih"
        }

    }

    /// crop x:y expressions use in_w/in_h vs out_w/out_h
    private static func cropXY(center: Bool, anchor: BurnInPosition) -> String {
        if center { return "x=(in_w-out_w)/2:y=(in_h-out_h)/2" }

        switch anchor {
        case .upperLeft:   return "x=0:y=0"
        case .upperCenter: return "x=(in_w-out_w)/2:y=0"
        case .upperRight:  return "x=in_w-out_w:y=0"

        case .middleLeft:  return "x=0:y=(in_h-out_h)/2"
        case .center:      return "x=(in_w-out_w)/2:y=(in_h-out_h)/2"
        case .middleRight: return "x=in_w-out_w:y=(in_h-out_h)/2"

        case .lowerLeft:   return "x=0:y=in_h-out_h"
        case .lowerCenter: return "x=(in_w-out_w)/2:y=in_h-out_h"
        case .lowerRight:  return "x=in_w-out_w:y=in_h-out_h"
        }
    }
    
    /// Preset scaling only (legacy behavior).
    /// Always evenize + square pixels to keep encoders happy.
    private static func scaleFilter(for scale: ScaleOption) -> String? {
        switch scale {
        case .oneToOne:
            return #"scale=ceil(iw/2)*2:ceil(ih/2)*2,setsar=1"#
        case .half:
            return #"scale=ceil(iw*0.5/2)*2:ceil(ih*0.5/2)*2,setsar=1"#
        case .quarter:
            return #"scale=ceil(iw*0.25/2)*2:ceil(ih*0.25/2)*2,setsar=1"#
        case .custom:
            // Custom is handled by scaleFilter(settings:)
            return nil
        }
    }


    // MARK: - Overlays (timecode / frame / filename)

    /// Uses metadata fps & start timecode precisely; groups by corner/edge & stacks lines to avoid overlap.
    /// IMPORTANT (Step 5): No AVFoundation probing here. All sizing uses ffmpeg expressions (main_w/main_h).
    private static func overlayFilters(input: URL,
                                       meta: MediaMetadata,
                                       settings: Settings) -> [String]? {
        // Quick exit if user disabled everything
        let wantTC   = settings.burnInTimecode
        let wantFr   = settings.burnInFrames
        let wantName = settings.burnInFilename
        guard wantTC || wantFr || wantName else { return nil }

        // FPS: prefer metadata; if missing, choose a conservative default.
        // (Avoid probing in command builder. Step 6 will ensure meta is populated early.)
        let fps: Double = {
            if let m = meta.nominalFPS, m.isFinite, m > 0 { return m }
            return 30.0
        }()

        // ----------------------------
        // Expression-based sizing (scale-aware at runtime)
        // ----------------------------
        // These are ffmpeg expressions evaluated at runtime. They adapt to final scaled output size.
        // Tune multipliers to taste.
        let fontsizeExpr    = "max(18, min(64, main_h*0.035))"
        let marginXExpr     = "max(16, main_h*0.020)"
        let marginYExpr     = "max(16, main_h*0.020)"
        let lineGapExpr     = "max(6,  main_h*0.008)"     // gap BETWEEN lines in a stack
        let boxBorderExpr   = "max(6,  main_h*0.010)"     // padding around text box

        // A stable per-line vertical increment.
        let lineHeightExpr  = "(\(fontsizeExpr)+\(lineGapExpr))"

        // ----------------------------
        // Color formatting
        // ----------------------------
        // drawtext expects colors like: white@0.85, 000000@0.35, etc.
        func rgba(_ hex: String, _ alpha: Double) -> String {
            let h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                       .replacingOccurrences(of: "#", with: "")
            return "\(h)@\(String(format: "%.3f", alpha))"
        }

        let fontColor = rgba(settings.overlayTextColorHex, settings.overlayTextColorAlpha)
        let boxColor  = rgba(settings.overlayBoxColorHex,  settings.overlayBoxColorAlpha)

        // ----------------------------
        // Prepare overlay "requests" (we will group & stack them per position)
        // ----------------------------
        struct Request { let position: BurnInPosition; let payload: String }
        var reqs: [Request] = []

        // 1) TIMECODE — drawtext native timecode with accurate start + rate
        if wantTC {
            let pos = settings.burnInTimecodePosition
            let (tcText, rateOpt) = timecodeDrawtextOptions(meta: meta, fps: fps)
            let payload = "timecode='\(tcText)':\(rateOpt):tc24hmax=1"
            reqs.append(.init(position: pos, payload: payload))
        }

        // 2) FRAMES — count, zero-padded to end-frame width, honoring start offset
        if wantFr {
            let pos = settings.burnInFramesPosition
            let start = max(0, startFrameFromMetadata(meta: meta, fps: fps))
            let width = frameNumberPadWidth(start: start, meta: meta, url: input, fps: fps)
            let payload = "text='%{eif\\:n+\(start)\\:d\\:\(width)}'"
            reqs.append(.init(position: pos, payload: payload))
        }

        // 3) FILENAME — sanitized for drawtext
        if wantName {
            let pos = settings.burnInFilenamePosition
            let escaped = escapeForDrawtext(input.lastPathComponent)
            let payload = "text='\(escaped)'"
            reqs.append(.init(position: pos, payload: payload))
        }

        // ----------------------------
        // Positioning expressions
        // ----------------------------
        func xExpr(for pos: BurnInPosition) -> String {
            switch pos {
            case .upperLeft, .middleLeft, .lowerLeft:
                return marginXExpr

            case .upperCenter, .lowerCenter, .center:
                return "(main_w-text_w)/2"

            case .upperRight, .middleRight, .lowerRight:
                // Right align: x = main_w - margin - text_w
                return "main_w-\(marginXExpr)-text_w"
            }
        }

        /// Computes y for a given position and stack index.
        /// Top/center/bottom bands stack in the direction that keeps them on-screen:
        /// - upper*: stack downward from top margin
        /// - lower*: stack upward from bottom margin
        /// - middle*: stack downward from vertical center (can be adjusted if you prefer centering the whole stack)
        func yExpr(for pos: BurnInPosition, idx: Int, count: Int) -> String {
            switch pos {
            case .upperLeft, .upperCenter, .upperRight:
                // y = margin + idx*lineHeight
                return "\(marginYExpr)+(\(idx))*\(lineHeightExpr)"

            case .lowerLeft, .lowerCenter, .lowerRight:
                // y = main_h - margin - (count-idx)*lineHeight
                return "main_h-\(marginYExpr)-(\(count - idx))*\(lineHeightExpr)"

            case .middleLeft, .middleRight, .center:
                return "(main_h-text_h)/2+(\(idx))*\(lineHeightExpr)"

            }
        }

        // ----------------------------
        // drawtext builder
        // ----------------------------
        func drawtextFilter(payload: String, pos: BurnInPosition, idx: Int, count: Int) -> String {
            let x = xExpr(for: pos)
            let y = yExpr(for: pos, idx: idx, count: count)

            // Core drawtext options:
            // - expression-based fontsize/margins
            // - boxed background
            // - boxborderw acts like padding (expression-based)
            return "drawtext=" +
                   "\(payload):" +
                   "fontsize=\(fontsizeExpr):" +
                   "fontcolor=\(fontColor):" +
                   "box=1:" +
                   "boxcolor=\(boxColor):" +
                   "boxborderw=\(boxBorderExpr):" +
                   "x=\(x):" +
                   "y=\(y)"
        }

        // ----------------------------
        // Group by position and build stacked drawtext filters (no overlap)
        // ----------------------------
        var filters: [String] = []
        let grouped = Dictionary(grouping: reqs, by: { $0.position })

        for (pos, group) in grouped {
            for (idx, req) in group.enumerated() {
                filters.append(drawtextFilter(payload: req.payload, pos: pos, idx: idx, count: group.count))
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
        parts.append("fix_bounds=1") // keep visible near edges

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

        // Y expressions per vertical anchor - NO SPACES around operators!
        let topY    = "\(margin)+\(idx)*\(lineStep)"
        let midY    = "(h-th)/2+\(idx)*\(lineStep)"
        let botY    = "h-th-\(margin)-\(idx)*\(lineStep)"

        // X expressions per horizontal anchor
        let leftX   = "\(margin)"
        let midX    = "(w-tw)/2"
        let rightX  = "w-tw-\(margin)"

        switch position {
        case .upperLeft:    return (leftX,  topY)
        case .upperCenter:  return (midX,   topY)
        case .upperRight:   return (rightX, topY)
        case .middleLeft:   return (leftX,  midY)
        case .center:       return (midX,   midY)
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

    /// Width to pad the frame counter. Uses start offset and (if known) total frames.
    private static func frameNumberPadWidth(start: Int, meta: MediaMetadata, url: URL, fps: Double) -> Int {
        var width = max(6, String(start).count)

        // Estimate total frames if we know duration & fps
        let drop = (meta.startTimecode ?? "").contains(";")
        let baseFPS: Int = {
            if fps.isFinite && fps > 0 {
                if abs(fps - 59.94) < 0.01 { return 60 }
                if abs(fps - 29.97) < 0.01 { return 30 }
                return max(1, Int(round(fps)))
            }
            return 30
        }()

        var duration = meta.durationSeconds
        if duration.isFinite && duration > 0 {
            let total = max(0, Int(round(duration * Double(baseFPS))))
            let end   = start + max(total - 1, 0)
            width = max(width, String(end).count)
        }

        return width
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

    // MARK: - Bypass helpers
    
    /// Preserve source timing (VFR) on output; avoid implicit CFR.
    /// NOTE: We intentionally avoid `-fps_mode vfr` for compatibility with older ffmpeg builds.
    /// `-vsync vfr` is sufficient to keep variable frame timing as long as we don't set `-r` or an fps filter.
    /// Future todo possibly check ffmpeg build for support?
    private static func applyVFRPassThrough(_ args: inout [String], outputExt: String) {
        args += ["-vsync", "vfr"]
        // Do NOT add "-fps_mode vfr" (older ffmpeg will error with "Unrecognized option 'fps_mode'")
    }

    private static func fourCCString(_ code: FourCharCode) -> String {
        var big = code.bigEndian
        return withUnsafePointer(to: &big) {
            $0.withMemoryRebound(to: UInt8.self, capacity: 4) { ptr in
                String(bytes: [ptr[0], ptr[1], ptr[2], ptr[3]], encoding: .macOSRoman) ?? ""
            }
        }
    }

    /// Choose encoder args to “stay in the same family” as the source when pixel changes are requested.
    private static func sameCodecEncoderArgs(forFourCC fourcc: String, crf: Int) -> [String] {
        // ProRes family & Apple intermediate (apch/apcn/ap4h/etc.)
        if fourcc.hasPrefix("ap") || fourcc.contains("prores") {
            // Use ProRes 422 HQ (profile 3) as a safe/edit-friendly default
            return ["-c:v", "prores_ks", "-profile:v", "3"]
        }
        // H.264
        if fourcc.contains("avc1") || fourcc.contains("h264") {
            return ["-c:v", "libx264", "-crf", "\(crf)", "-preset", "medium"]
        }
        // HEVC
        if fourcc.contains("hvc1") || fourcc.contains("hev1") || fourcc.contains("hevc") {
            return ["-c:v", "libx265", "-crf", "\(crf)", "-preset", "medium"]
        }
        // Fallback: ProRes HQ (visually robust, widely compatible)
        return ["-c:v", "prores_ks", "-profile:v", "3"]
    }
}
