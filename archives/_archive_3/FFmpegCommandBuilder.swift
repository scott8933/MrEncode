// =============================
// File: FFmpegCommandBuilder.swift
// =============================
import Foundation

enum FFmpegCommandBuilder {

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
        args += ["-c:v", "libx265"]
        args += ["-pix_fmt", "yuv420p10le"]
        args += ["-profile:v", "main10"]
        args += ["-crf", String(settings.qualityCRF)]
        args += ["-preset", "fast"]

        // Video filter chain (scale + overlays)
        var filters: [String] = []
        if let s = scaleFilter(for: settings.scale) {
            filters.append(s)
        }
        filters.append(contentsOf: overlayFilters(for: settings, input: input, meta: meta))
        if !filters.isEmpty {
            args += ["-vf", filters.joined(separator: ",")]
        }

        // Audio (simple heuristic to avoid warnings on video-only sources)
        if likelyHasAudioStream(input) {
            args += ["-c:a", "aac", "-b:a", "128k"]
        } else {
            args += ["-an"]
        }

        // Apple playback tag
        args += ["-tag:v", "hvc1"]

        // Optional: NCLC tagging (very light mapping; extend as needed)
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
        case .half: return #"scale=trunc(iw*0.5/2)*2:trunc(ih*0.5/2)*2"#
        case .quarter: return #"scale=trunc(iw*0.25/2)*2:trunc(ih*0.25/2)*2"#
        }
    }

    // MARK: - Overlays (stacking to avoid overlap)

    /// Build drawtext filters for enabled overlays.
    /// If multiple overlays share the same position, they are stacked with a small gap.
    private static func overlayFilters(for settings: Settings, input: URL, meta: MediaMetadata) -> [String] {
        struct OverlaySpec { let text: String; let pos: BurnInPosition; let isPrebuilt: Bool }

        var specs: [OverlaySpec] = []

        // Frames (start at clip timecode offset; zero-padded to end frame width)
        // Frames (start at clip timecode offset; zero-padded to end-frame width)
        if settings.burnInFrames {
            let xy = stackedXY(for: settings.burnInFramesPosition, index: 0, margin: 10, gap: 4)

            if let off = startFrameOffset(from: meta) {
                // Prefer width based on END frame if we know duration + fps; else at least 6.
                var padWidth = max(6, String(off).count)
                if let fps = meta.nominalFPS, let dur = meta.durationSeconds {
                    let drop = (meta.startTimecode ?? "").contains(";")
                    let base = timecodeBaseFPS(from: fps, dropFrame: drop)
                    let totalFrames = max(0, Int(round(dur * Double(base))))
                    let endFrame = off + max(totalFrames - 1, 0)
                    padWidth = max(padWidth, String(endFrame).count)
                }

                #if DEBUG
                print("Overlay[FRM]: \(input.lastPathComponent) offset=\(off) width=\(padWidth)")
                #endif

                let frameFilter = prebuiltFrameCounterDrawtext(frameOffset: off, padWidth: padWidth, x: xy.x, y: xy.y)
                specs.append(.init(text: frameFilter, pos: settings.burnInFramesPosition, isPrebuilt: true))
            } else {
                // Fallback: zero-based, still padded to look tidy
                let padWidth = 6
                let expr = "%{eif\\:n\\:d\\:\(padWidth)}"
                let menloPath = "/System/Library/Fonts/Menlo.ttc"
                let fallback = "drawtext=fontfile='\(menloPath)':text='\(expr)':" +
                               "fontcolor=white:fontsize=18:box=1:boxcolor=black@0.80:" +
                               "boxborderw=6:x=\(xy.x):y=\(xy.y)"
                specs.append(.init(text: fallback, pos: settings.burnInFramesPosition, isPrebuilt: true))
            }
        }




        // Timecode:
        // If we have a startTC + fps, use drawtext timecode mode; else fall back to pts clock.
        if settings.burnInTimecode {
            if let start = meta.startTimecode, let fps = meta.nominalFPS, fps > 0 {
                let xy = stackedXY(for: settings.burnInTimecodePosition, index: 0, margin: 10, gap: 4)
                let rate = fpsToRational(fps)
                
                #if DEBUG
                print("Overlay[TC]: \(input.lastPathComponent) start=\(start) r=\(rate)")
                #endif
                
                let tc = prebuiltTimecodeDrawtext(startTC: start,
                                                  rate: rate,
                                                  x: xy.x, y: xy.y)
                specs.append(.init(text: tc, pos: settings.burnInTimecodePosition, isPrebuilt: true))
            } else {
                
                #if DEBUG
                print("Overlay[PTS]: \(input.lastPathComponent) meta.startTimecode=\(String(describing: meta.startTimecode)) fps=\(String(describing: meta.nominalFPS))")
                #endif
                
                specs.append(.init(text: "%{pts\\:hms}", pos: settings.burnInTimecodePosition, isPrebuilt: false))
            }

        }

        // Filename (basename only)
        if settings.burnInFilename {
            let base = input.deletingPathExtension().lastPathComponent
            let escaped = escapeForDrawtextLiteral(base)
            specs.append(.init(text: escaped, pos: settings.burnInFilenamePosition, isPrebuilt: false))
        }

        guard !specs.isEmpty else { return [] }

        // Visual tuning for all overlays
        let fontSize = 18
        let boxAlpha = "0.80"
        let pad = 6
        let margin = 10
        let gap = 4

        // Group by position, then stack per group
        let groups = Dictionary(grouping: specs, by: { $0.pos })

        var filters: [String] = []
        for (pos, items) in groups {
            for (idx, spec) in items.enumerated() {
                let xy = stackedXY(for: pos, index: idx, margin: margin, gap: gap)

                if spec.isPrebuilt, spec.text.hasPrefix("drawtext=") {
                    // Replace final x/y in the prebuilt filter with stacked values
                    let rebuilt = spec.text.replacingOccurrences(
                        of: #"x=[^:]*:y=[^:]*"#,
                        with: "x=\(xy.x):y=\(xy.y)",
                        options: .regularExpression
                    )
                    filters.append(rebuilt)
                } else {
                    filters.append(
                        drawtext(text: spec.text,
                                 size: fontSize,
                                 x: xy.x, y: xy.y,
                                 boxAlpha: boxAlpha, pad: pad)
                    )
                }
            }
        }
        return filters
    }

    /// Compute x/y expressions for a position, stacked by index.
    /// Uses `th` (text height) so each subsequent item offsets by `(th + gap)`.
    private static func stackedXY(for pos: BurnInPosition, index: Int, margin m: Int, gap g: Int)
    -> (x: String, y: String) {
        let down  = index == 0 ? "0"  : "(\(index))*(th+\(g))"
        let up    = index == 0 ? "0"  : "-(\(index))*(th+\(g))"

        switch pos {
        // Top row: stack downward
        case .upperLeft:   return ("\(m)", "\(m)+\(down)")
        case .upperCenter: return ("(w-tw)/2", "\(m)+\(down)")
        case .upperRight:  return ("w-tw-\(m)", "\(m)+\(down)")

        // Middle row: stack downward from vertical center
        case .middleLeft:  return ("\(m)", "(h-th)/2+\(down)")
        case .middleRight: return ("w-tw-\(m)", "(h-th)/2+\(down)")

        // Bottom row: stack upward
        case .lowerLeft:   return ("\(m)", "h-th-\(m)\(up)")
        case .lowerCenter: return ("(w-tw)/2", "h-th-\(m)\(up)")
        case .lowerRight:  return ("w-tw-\(m)", "h-th-\(m)\(up)")
        }
    }

    /// Prebuilt drawtext for timecode mode (uses Menlo via fontfile, rational fps with r=).
    private static func prebuiltTimecodeDrawtext(startTC: String, rate: String, x: String, y: String) -> String {
        let menloPath = "/System/Library/Fonts/Menlo.ttc"
        let boxAlpha = "0.80"
        let pad = 6
        let fontSize = 18

        // drawtext honors drop-frame if startTC has a semicolon (HH:MM:SS;FF)
        let tcEsc = escapeForFilterArg(startTC)  // ← escape the colons inside the value

        return "drawtext=fontfile='\(menloPath)':timecode='\(tcEsc)':r=\(rate):" +
               "fontcolor=white:fontsize=\(fontSize):box=1:boxcolor=black@\(boxAlpha):" +
               "boxborderw=\(pad):x=\(x):y=\(y)"
    }



    /// Single drawtext filter string using Menlo.ttc directly (bypasses fontconfig).
    private static func drawtext(text: String,
                                 size: Int,
                                 x: String, y: String,
                                 boxAlpha: String, pad: Int) -> String {
        let menloPath = "/System/Library/Fonts/Menlo.ttc"  // macOS built-in
        return "drawtext=fontfile='\(menloPath)':text='\(text)':" +
               "fontcolor=white:fontsize=\(size):" +
               "box=1:boxcolor=black@\(boxAlpha):boxborderw=\(pad):" +
               "x=\(x):y=\(y)"
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
            return nil // "no change" or not mapped
        }
    }

    // MARK: - Misc

    /// Fast heuristic; use ffprobe for certainty if you need exact detection.
    private static func likelyHasAudioStream(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mov","mp4","m4v","mxf","mkv","avi","mpg","mpeg","wav","aif","aiff"].contains(ext)
    }
    
    // Extract only the output-related arguments for Deadline job submission
    static func outputArgsOnly(item: MediaItem, output: URL, settings: Settings) -> String {
        let full = buildArgs(item: item, output: output, settings: settings)

        // Drop the leading `-hide_banner -y -i INPUT`
        var trimmed = full
        if let inputIndex = trimmed.firstIndex(of: "-i") {
            // Remove everything up to and including the input file
            let i = trimmed.index(after: inputIndex)
            if i < trimmed.endIndex { trimmed.removeSubrange(...i) }
        }

        // Join as plain string (Deadline expects no quotes)
        return trimmed.joined(separator: " ")
    }
    
    
    // Returns the "output args" portion suitable for Deadline's FFmpeg plugin,
    // given a full args array and the known input/output paths.
    // - Strips -hide_banner and -y
    // - Strips the leading "-i <input>"
    // - Strips the trailing "<output>"
    static func ffmpegOutputArgs(fromFullArgs full: [String], input: URL, output: URL) -> String {
        var tokens = full

        // 1) Remove harmless globals
        tokens.removeAll { $0 == "-hide_banner" || $0 == "-y" }

        // 2) Remove the input pair: -i <inputPath>
        if let iIdx = tokens.firstIndex(of: "-i") {
            let pathIdx = tokens.index(after: iIdx)
            if pathIdx < tokens.endIndex && tokens[pathIdx] == input.path {
                tokens.removeSubrange(iIdx...pathIdx)
            } else {
                // Fallback: remove just "-i" if path didn't match for any reason
                tokens.remove(at: iIdx)
            }
        }

        // 3) Remove the final output path (if present)
        if let outIdx = tokens.lastIndex(of: output.path) {
            tokens.remove(at: outIdx)
        }

        // 4) Join — Deadline's FFmpeg plugin expects a single space-separated string
        return tokens.joined(separator: " ")
    }
    
    // MARK: - Timecode → frame math

    /// Parse "HH:MM:SS:FF" (NDF) or "HH:MM:SS;FF" (DF).
    private static func parseTimecode(_ tc: String) -> (h:Int, m:Int, s:Int, f:Int, drop: Bool)? {
        let drop = tc.contains(";")
        // Normalize by replacing ';' with ':' for splitting
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
        if near(nominal, 25.0) { return 25 }
        if near(nominal, 29.97) || near(nominal, 30.0) { return 30 }
        if near(nominal, 50.0) { return 50 }
        if near(nominal, 59.94) || near(nominal, 60.0) { return 60 }
        return max(1, Int(round(nominal)))
    }

    /// SMPTE total frames from 00:00:00:00 to H:M:S:F.
    /// For 30/60/120 DF: drop 2/4/8 frames per minute except every 10th minute.
    private static func framesFromTimecode(h:Int, m:Int, s:Int, f:Int, base:Int, drop: Bool) -> Int {
        let totalSeconds = h * 3600 + m * 60 + s
        if drop, (base % 30 == 0) {
            let dropPerMin = 2 * (base / 30)                 // 30→2, 60→4, 120→8
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
    /// Uses: %{eif\:n+OFFSET\:%0Nd}  (colons escaped for filter parsing)
    private static func prebuiltFrameCounterDrawtext(frameOffset: Int,
                                                     padWidth: Int,
                                                     x: String, y: String) -> String {
        let menloPath = "/System/Library/Fonts/Menlo.ttc"
        let boxAlpha = "0.80"
        let pad = 6
        let fontSize = 18

        // printf-style format with zero padding, e.g. %06d
        let fmt = "%0\(max(1, padWidth))d"
        let expr = "%{eif\\:n+\(frameOffset)\\:d\\:\(max(1, padWidth))}"

        return "drawtext=fontfile='\(menloPath)':text='\(expr)':" +
               "fontcolor=white:fontsize=\(fontSize):box=1:boxcolor=black@\(boxAlpha):" +
               "boxborderw=\(pad):x=\(x):y=\(y)"
    }
    
    /// Map a floating fps to a rational string suitable for drawtext r=
    /// Handles common NTSC rates; falls back to rounded integer /1.
    private static func fpsToRational(_ fps: Double) -> String {
        // Common NTSC-ish
        let table: [(Double, String)] = [
            (23.976, "24000/1001"),
            (29.97,  "30000/1001"),
            (59.94,  "60000/1001"),
            (119.88, "120000/1001"),
            (47.952, "48000/1001")
        ]
        for (t, r) in table where abs(fps - t) < 0.01 { return r }

        // Common integers
        let ints: [Double] = [24, 25, 30, 50, 60, 120]
        for v in ints where abs(fps - v) < 0.01 { return "\(Int(v))/1" }

        // Fallback: nearest integer
        return "\(Int(round(fps)))/1"
    }
    
    /// Escape a value used as a filter option argument (e.g., timecode='...').
    private static func escapeForFilterArg(_ s: String) -> String {
        var r = s.trimmingCharacters(in: .whitespacesAndNewlines)
        r = r.replacingOccurrences(of: "\\", with: "\\\\")
        r = r.replacingOccurrences(of: ":", with: "\\:")  // ← critical for drawtext/timecode
        r = r.replacingOccurrences(of: "'", with: "\\'")
        return r
    }

}
