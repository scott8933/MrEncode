// =============================
// File: FFmpegCommandBuilder.swift
// =============================

import Foundation
import AVFoundation

enum FFmpegCommandBuilder {

    // MARK: - Constants

    private static let menloPath     = "/System/Library/Fonts/Menlo.ttc"
    private static let defaultBoxA   = "0.80"
    private static let defaultPad    = 6
    private static let defaultMargin = 10
    private static let defaultGap    = 4

    // MARK: - Public entry points

    /// Legacy/URL-style entry (no per-file metadata).
    static func buildArgs(input: URL, output: URL, settings: Settings) -> [String] {
        buildArgs(input: input, output: output, settings: settings, meta: .empty)
    }

    /// Preferred entry: use the MediaItem so overlays can use extracted metadata (e.g., timecode).
    static func buildArgs(item: MediaItem, output: URL, settings: Settings) -> [String] {
        buildArgs(input: item.url, output: output, settings: settings, meta: item.meta)
    }

    // MARK: - Core builder

    private static func buildArgs(input: URL, output: URL, settings: Settings, meta: MediaMetadata) -> [String] {
        var args: [String] = []

        // Quiet-ish, overwrite existing
        args += ["-hide_banner", "-y"]

        // Input
        args += ["-i", input.path]

        // Video
        args += ["-c:v", "libx265",
                 "-pix_fmt", "yuv420p10le",
                 "-profile:v", "main10",
                 "-crf", String(settings.qualityCRF),
                 "-preset", "fast"]

        // Video filter chain (scale + overlays)
        var filters: [String] = []
        if let s = scaleFilter(for: settings.scale) { filters.append(s) }
        filters += overlayFilters(for: settings, input: input, meta: meta)
        if !filters.isEmpty { args += ["-vf", filters.joined(separator: ",")] }

        // Audio (simple heuristic to avoid warnings on video-only sources)
        if likelyHasAudioStream(input) {
            args += ["-c:a", "aac", "-b:a", "128k"]
        } else {
            args += ["-an"]
        }

        // Apple playback tag
        args += ["-tag:v", "hvc1"]

        // Optional: NCLC tagging (light mapping; extend as needed)
        if let t = nclcTriplet(for: settings.nclcTag) {
            args += ["-color_primaries", t.primaries,
                     "-color_trc",       t.trc,
                     "-colorspace",      t.matrix]
        }

        // Output
        args.append(output.path)
        return args
    }

    // MARK: - Scale

    private static func scaleFilter(for scale: ScaleOption) -> String? {
        switch scale {
        case .oneToOne: return nil
        case .half:     return #"scale=trunc(iw*0.5/2)*2:trunc(ih*0.5/2)*2"#
        case .quarter:  return #"scale=trunc(iw*0.25/2)*2:trunc(ih*0.25/2)*2"#
        }
    }

    // MARK: - Responsive font sizing (based on *final* render size)

    private static func finalScaleMultiplier(for scale: ScaleOption) -> Double {
        switch scale {
        case .oneToOne: return 1.0
        case .half:     return 0.5
        case .quarter:  return 0.25
        }
    }

    private static func inputVideoHeight(_ url: URL) -> Int {
        let asset = AVAsset(url: url)
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            return Int(abs(size.height).rounded())
        }
        return 1080 // fallback
    }

    /// Compute font size from the *final* render height (post-scale).
    /// `basePct` is the dial you can tune later (e.g., 0.030–0.045).
    private static func fontSizeForFinalRender(input: URL,
                                               scale: ScaleOption,
                                               basePct: Double = 0.035,
                                               min: Int = 18,
                                               max: Int = 256) -> Int {
        let inH = inputVideoHeight(input)
        let finalH = Double(inH) * finalScaleMultiplier(for: scale)
        let px = Int((finalH * basePct).rounded())
        return Swift.max(min, Swift.min(px, max))
    }

    /// Derive a numeric line height for stacking overlays cleanly.
    /// Using ~1.25× font size as a simple line box approximation.
    private static func lineHeight(for fontSize: Int) -> Int {
        return Int((Double(fontSize) * 1.25).rounded())
    }

    // MARK: - Overlays (stacking to avoid overlap)
    
    /// FFmpeg color literal: 0xRRGGBB[@alpha]
    private static func ffColor(hex: String, alpha: Double? = nil) -> String {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                       .replacingOccurrences(of: "#", with: "")
                       .uppercased()
        let rgb = clean.count == 6 ? clean : "FFFFFF"
        if let a = alpha { return String(format: "0x%@@%.2f", rgb, a) }
        return "0x\(rgb)"
    }

    /// Build drawtext filters for enabled overlays.
    /// If multiple overlays share the same position, they are stacked with a small gap.
    private static func overlayFilters(for settings: Settings, input: URL, meta: MediaMetadata) -> [String] {
        struct OverlaySpec { let text: String; let pos: BurnInPosition; let isPrebuilt: Bool }
        var specs: [OverlaySpec] = []

        // One font size for all overlays, derived from final render height (after scale).
        let fontSize = fontSizeForFinalRender(input: input, scale: settings.scale)
        let lineH    = lineHeight(for: fontSize)
        
        let textColor = ffColor(hex: settings.overlayTextColorHex,
                                alpha: settings.overlayTextColorAlpha)

        let boxSpec: String = {
            if settings.overlayBoxEnabled {
                let bc = ffColor(hex: settings.overlayBoxColorHex,
                                 alpha: settings.overlayBoxColorAlpha)
                return "box=1:boxcolor=\(bc):boxborderw=\(defaultPad)"
            } else {
                return "box=0:boxborderw=\(defaultPad)"
            }
        }()


        // Frames (start at clip timecode offset; zero-padded to end-frame width)
        if settings.burnInFrames {
            
            let xy = stackedXY(for: settings.burnInFramesPosition,
                               index: 0,
                               margin: defaultMargin,
                               gap: defaultGap,
                               lineH: lineH)
            
            if let off = startFrameOffset(from: meta) {
                // Prefer width based on END frame if we know duration + fps; else at least 6.
                var padWidth = max(6, String(off).count)
                if let fps = meta.nominalFPS, let dur = meta.durationSeconds {
                    let drop = (meta.startTimecode ?? "").contains(";")
                    let base = timecodeBaseFPS(from: fps, dropFrame: drop)
                    let totalFrames = max(0, Int(round(dur * Double(base))))
                    let endFrame    = off + max(totalFrames - 1, 0)
                    padWidth = max(padWidth, String(endFrame).count)
                }

                #if DEBUG
                print("Overlay[FRM]: \(input.lastPathComponent) offset=\(off) width=\(padWidth)")
                #endif

                // Place later during group stacking; x/y placeholders here
                let placeholderXY = stackedXY(for: settings.burnInFramesPosition, index: 0,
                                              margin: defaultMargin, gap: defaultGap, lineH: lineH)
                let frameFilter = prebuiltFrameCounterDrawtext(frameOffset: off,
                                                               padWidth: padWidth,
                                                               x: xy.x, y: xy.y,
                                                               fontSize: fontSize,
                                                               textColor: textColor,
                                                               boxSpec: boxSpec)

                specs.append(.init(text: frameFilter, pos: settings.burnInFramesPosition, isPrebuilt: true))
            } else {
                // Fallback: zero-based, still padded to look tidy
                let padWidth = 6
                let xy = stackedXY(for: settings.burnInFramesPosition, index: 0,
                                   margin: defaultMargin, gap: defaultGap, lineH: lineH)
                let expr = "%{eif\\:n\\:d\\:\(padWidth)}"
                let fallback = "drawtext=fontfile='\(menloPath)':text='\(expr)':" +
                               "fontcolor=\(textColor):fontsize=\(fontSize):\(boxSpec):" +
                               "x=\(xy.x):y=\(xy.y):fix_bounds=1"
                specs.append(.init(text: fallback, pos: settings.burnInFramesPosition, isPrebuilt: true))
            }
        }

        // Timecode: use drawtext timecode mode if we have startTC + fps, else fall back to pts clock.
        if settings.burnInTimecode {
            if let start = meta.startTimecode, let fps = meta.nominalFPS, fps > 0 {
                let xy = stackedXY(for: settings.burnInTimecodePosition, index: 0,
                                   margin: defaultMargin, gap: defaultGap, lineH: lineH)
                let rate = fpsToRational(fps)
                #if DEBUG
                print("Overlay[TC]: \(input.lastPathComponent) start=\(start) r=\(rate)")
                #endif
                let tc = prebuiltTimecodeDrawtext(startTC: start, rate: rate,
                                                  x: xy.x, y: xy.y,
                                                  fontSize: fontSize,
                                                  textColor: textColor,
                                                  boxSpec: boxSpec)

                specs.append(.init(text: tc, pos: settings.burnInTimecodePosition, isPrebuilt: true))
            } else {
                #if DEBUG
                print("Overlay[PTS]: \(input.lastPathComponent) meta.startTimecode=\(String(describing: meta.startTimecode)) fps=\(String(describing: meta.nominalFPS))")
                #endif
                let xy = stackedXY(for: settings.burnInTimecodePosition, index: 0,
                                   margin: defaultMargin, gap: defaultGap, lineH: lineH)
                specs.append(.init(text: "%{pts\\:hms}",
                                   pos: settings.burnInTimecodePosition, isPrebuilt: false))
            }
        }

        // Filename (now shows the full basename INCLUDING extension)
        if settings.burnInFilename {
            let nameWithExt = input.lastPathComponent
            let escaped     = escapeForDrawtextLiteral(nameWithExt)
            specs.append(.init(text: escaped, pos: settings.burnInFilenamePosition, isPrebuilt: false))
        }

        guard !specs.isEmpty else { return [] }

        // Group by position, then stack per group using numeric line height so sizes don't overlap.
        let groups = Dictionary(grouping: specs, by: { $0.pos })

        var filters: [String] = []
        for (pos, items) in groups {
            for (idx, spec) in items.enumerated() {
                // Recompute x/y per stack index with the resolved line height
                let xy = stackedXY(for: pos, index: idx, margin: defaultMargin, gap: defaultGap, lineH: lineH)

                if spec.isPrebuilt, spec.text.hasPrefix("drawtext=") {
                    // Replace final x/y in the prebuilt filter with stacked values and force fix_bounds=1
                    var rebuilt = spec.text.replacingOccurrences(
                        of: #"x=[^:]*:y=[^:]*"#,
                        with: "x=\(xy.x):y=\(xy.y)",
                        options: .regularExpression
                    )
                    if !rebuilt.contains("fix_bounds=") {
                        rebuilt.append(":fix_bounds=1")
                    }
                    filters.append(rebuilt)
                } else {
                    filters.append(
                        drawtext(text: spec.text,
                                 size: fontSize,
                                 x: xy.x, y: xy.y,
                                 textColor: textColor,
                                 boxSpec: boxSpec)
                    )
                }
            }
        }
        return filters
    }

    /// Compute x/y expressions for a position, stacked by index.
    /// Uses a numeric line height derived from the chosen font size to avoid overlap.
    private static func stackedXY(for pos: BurnInPosition, index: Int, margin m: Int, gap g: Int, lineH: Int)
    -> (x: String, y: String) {
        let offset = index * (lineH + g)

        switch pos {
        // Top row: stack downward from margin
        case .upperLeft:   return ("\(m)", "\(m + offset)")
        case .upperCenter: return ("(w-tw)/2", "\(m + offset)")
        case .upperRight:  return ("w-tw-\(m)", "\(m + offset)")

        // Middle row: stack downward from center
        case .middleLeft:  return ("\(m)", "(h-th)/2+\(offset)")
        case .middleRight: return ("w-tw-\(m)", "(h-th)/2+\(offset)")

        // Bottom row: stack upward from bottom margin
        case .lowerLeft:   return ("\(m)", "h-th-\(m + offset)")
        case .lowerCenter: return ("(w-tw)/2", "h-th-\(m + offset)")
        case .lowerRight:  return ("w-tw-\(m)", "h-th-\(m + offset)")
        }
    }

    // MARK: - Drawtext helpers

    /// Prebuilt drawtext for timecode mode (uses Menlo via fontfile, rational fps with r=).
    private static func prebuiltTimecodeDrawtext(startTC: String,
                                                 rate: String,
                                                 x: String, y: String,
                                                 fontSize: Int,
                                                 textColor: String,
                                                 boxSpec: String) -> String {
        let tcEsc = escapeForFilterArg(startTC)
        return "drawtext=fontfile='\(menloPath)':timecode='\(tcEsc)':r=\(rate):" +
               "fontcolor=\(textColor):fontsize=\(fontSize):\(boxSpec):" +
               "x=\(x):y=\(y):fix_bounds=1"
    }


    /// Single drawtext filter string using Menlo.ttc directly (bypasses fontconfig).
    private static func drawtext(text: String,
                                 size: Int,
                                 x: String, y: String,
                                 textColor: String,
                                 boxSpec: String) -> String {
        return "drawtext=fontfile='\(menloPath)':text='\(text)':" +
               "fontcolor=\(textColor):fontsize=\(size):\(boxSpec):" +
               "x=\(x):y=\(y):fix_bounds=1"
    }


    /// Escape literal text for drawtext's single-quoted `text='...'` argument.
    private static func escapeForDrawtextLiteral(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(of: "\\", with: "\\\\")
        r = r.replacingOccurrences(of: ":", with: "\\:")
        r = r.replacingOccurrences(of: "'", with: "\\'")
        r = r.replacingOccurrences(of: ",", with: "\\,")
        return r
    }

    /// Escape a value used as a filter option argument (e.g., timecode='...').
    private static func escapeForFilterArg(_ s: String) -> String {
        var r = s.trimmingCharacters(in: .whitespacesAndNewlines)
        r = r.replacingOccurrences(of: "\\", with: "\\\\")
        r = r.replacingOccurrences(of: ":", with: "\\:")
        r = r.replacingOccurrences(of: "'", with: "\\'")
        return r
    }

    // MARK: - NCLC (light mapping; extend to your full list)

    /// Map your NCLC dropdown label to ffmpeg triplet flags.
    private static func nclcTriplet(for label: String) -> (primaries: String, trc: String, matrix: String)? {
        switch label {
        case "1-1-1 (BT.709)":
            return ("bt709", "bt709", "bt709")
        case "9-16-9 (BT.2020)", "9-1-9 (BT.2020 SDR)":
            return ("bt2020", "bt2020_10bit", "bt2020nc")
        case "12-16-1 (P3-D65)", "12-13-1 (DisplayP3)":
            return ("smpte431", "unknown", "unknown")
        default:
            return nil // "No Change" or not mapped
        }
    }

    // MARK: - Misc

    /// Fast heuristic; use ffprobe for certainty if you need exact detection.
    private static func likelyHasAudioStream(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mov","mp4","m4v","mxf","mkv","avi","mpg","mpeg","wav","aif","aiff"].contains(ext)
    }

    // MARK: - Output args shaping (Deadline)

    /// Deprecated: use `ffmpegOutputArgs(fromFullArgs:input:output:)`.
    @available(*, deprecated, message: "Use ffmpegOutputArgs(fromFullArgs:input:output:)")
    static func outputArgsOnly(item: MediaItem, output: URL, settings: Settings) -> String {
        let full = buildArgs(item: item, output: output, settings: settings)
        return ffmpegOutputArgs(fromFullArgs: full, input: item.url, output: output)
    }

    /// Build the "output args" portion suitable for Deadline's FFmpeg plugin from full args.
    /// - Strips: `-hide_banner`, `-y`, the leading `-i <input>` pair, and the trailing `<output>`.
    static func ffmpegOutputArgs(fromFullArgs full: [String], input: URL, output: URL) -> String {
        var tokens = full

        // Remove harmless globals
        tokens.removeAll { $0 == "-hide_banner" || $0 == "-y" }

        // Remove the input pair: -i <inputPath>
        if let iIdx = tokens.firstIndex(of: "-i") {
            let pathIdx = tokens.index(after: iIdx)
            if pathIdx < tokens.endIndex && tokens[pathIdx] == input.path {
                tokens.removeSubrange(iIdx...pathIdx)
            } else {
                tokens.remove(at: iIdx) // fallback
            }
        }

        // Remove the final output path (if present)
        if let outIdx = tokens.lastIndex(of: output.path) {
            tokens.remove(at: outIdx)
        }

        // Join — Deadline expects a single space-separated string
        return tokens.joined(separator: " ")
    }

    // MARK: - Timecode → frame math

    /// Parse "HH:MM:SS:FF" (NDF) or "HH:MM:SS;FF" (DF).
    private static func parseTimecode(_ tc: String) -> (h:Int, m:Int, s:Int, f:Int, drop: Bool)? {
        let drop = tc.contains(";")
        let clean = tc.replacingOccurrences(of: ";", with: ":").trimmingCharacters(in: .whitespaces)
        let parts = clean.split(separator: ":").map(String.init)
        guard parts.count == 4,
              let h = Int(parts[0]), let m = Int(parts[1]),
              let s = Int(parts[2]), let f = Int(parts[3]) else { return nil }
        return (h, m, s, f, drop)
    }

    /// Choose a timecode base (integer fps) given nominal fps + drop-frame flag.
    private static func timecodeBaseFPS(from nominal: Double, dropFrame: Bool) -> Int {
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.02 }
        if dropFrame {
            if near(nominal, 29.97) { return 30 }
            if near(nominal, 59.94) { return 60 }
            if near(nominal, 119.88) { return 120 }
        }
        if near(nominal, 23.976) || near(nominal, 24.0) { return 24 }
        if near(nominal, 25.0)   { return 25 }
        if near(nominal, 29.97) || near(nominal, 30.0) { return 30 }
        if near(nominal, 50.0)   { return 50 }
        if near(nominal, 59.94) || near(nominal, 60.0) { return 60 }
        return max(1, Int(round(nominal)))
    }

    /// SMPTE total frames from 00:00:00:00 to H:M:S:F.
    /// For 30/60/120 DF: drop 2/4/8 frames per minute except every 10th minute.
    private static func framesFromTimecode(h:Int, m:Int, s:Int, f:Int, base:Int, drop: Bool) -> Int {
        let totalSeconds = h * 3600 + m * 60 + s
        if drop, (base % 30 == 0) {
            let dropPerMin = 2 * (base / 30)           // 30→2, 60→4, 120→8
            let totalMins  = h * 60 + m
            let dropped    = dropPerMin * (totalMins - totalMins / 10)
            return totalSeconds * base + f - dropped
        }
        return totalSeconds * base + f
    }

    /// Compute the starting frame offset from media metadata (nil if missing).
    private static func startFrameOffset(from meta: MediaMetadata) -> Int? {
        guard let tc = meta.startTimecode, let fps = meta.nominalFPS,
              let p = parseTimecode(tc) else { return nil }
        let base = timecodeBaseFPS(from: fps, dropFrame: p.drop)
        return framesFromTimecode(h: p.h, m: p.m, s: p.s, f: p.f, base: base, drop: p.drop)
    }

    /// Frame counter with start-frame offset, zero-padded to `padWidth` digits.
    /// Uses: %{eif\:EXPR\:d\:WIDTH}  (colons escaped for filter parsing)
    private static func prebuiltFrameCounterDrawtext(frameOffset: Int,
                                                     padWidth: Int,
                                                     x: String, y: String,
                                                     fontSize: Int,
                                                     textColor: String,
                                                     boxSpec: String) -> String {
        let expr = "%{eif\\:n+\(frameOffset)\\:d\\:\(max(1, padWidth))}"
        return "drawtext=fontfile='\(menloPath)':text='\(expr)':" +
               "fontcolor=\(textColor):fontsize=\(fontSize):\(boxSpec):" +
               "x=\(x):y=\(y):fix_bounds=1"
    }


    /// Map a floating fps to a rational string suitable for drawtext r=.
    /// Handles common NTSC rates; falls back to rounded integer /1.
    private static func fpsToRational(_ fps: Double) -> String {
        let table: [(Double, String)] = [
            (23.976, "24000/1001"),
            (29.97,  "30000/1001"),
            (59.94,  "60000/1001"),
            (119.88, "120000/1001"),
            (47.952, "48000/1001")
        ]
        for (t, r) in table where abs(fps - t) < 0.01 { return r }

        let ints: [Double] = [24, 25, 30, 50, 60, 120]
        for v in ints where abs(fps - v) < 0.01 { return "\(Int(v))/1" }

        return "\(Int(round(fps)))/1"
    }
}
