//
//  FFmpegCommandBuilder.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/2/25.
//

import Foundation

// MARK: - FFmpeg Command Builder

enum FFmpegCommandBuilder {
    /// Build ffmpeg argv for HEVC encode using current settings.
    static func buildArgs(input: URL, output: URL, settings: Settings) -> [String] {
        var args: [String] = [
            "-hide_banner",
            "-y",
            "-i", input.path,
            "-c:v", "libx265",
            "-pix_fmt", "yuv420p10le",
            "-profile:v", "main10",
            "-crf", String(settings.qualityCRF),
            "-preset", "fast",
            "-c:a", "aac",
            "-b:a", "128k",
            "-tag:v", "hvc1"
        ]

        // Optional scale
        if let vf = scaleFilter(for: settings.scale) {
            args += ["-vf", vf]
        }

        // Optional NCLC tagging
        if let nclc = nclcTriplet(for: settings.nclcTag) {
            args += ["-color_primaries", nclc.primaries,
                     "-color_trc",       nclc.trc,
                     "-colorspace",      nclc.matrix]
        }

        args.append(output.path)
        return args
    }

    /// If you need only the video filter string elsewhere.
    static func scaleFilter(for scale: ScaleOption) -> String? {
        switch scale {
        case .oneToOne: return nil
        case .half:     return #"scale=trunc(iw*0.5/2)*2:trunc(ih*0.5/2)*2"#
        case .quarter:  return #"scale=trunc(iw*0.25/2)*2:trunc(ih*0.25/2)*2"#
        }
    }

    /// Map UI choice to ffmpeg (primaries, trc, matrix). `nil` means "no change".
    static func nclcTriplet(for choice: String) -> (primaries: String, trc: String, matrix: String)? {
        switch choice {
        case "no change": return nil

        // BT.709 / sRGB family
        case "1-1-1 (BT.709)":             return ("bt709", "bt709", "bt709")
        case "1-13-1 (sRGB)":              return ("bt709", "iec61966-2-1", "bt709")
        case "1-4-1 (BT.709 γ2.2)":        return ("bt709", "gamma22", "bt709")
        case "1-5-1 (BT.709 γ2.8)":        return ("bt709", "gamma28", "bt709")

        // Rec.601
        case "6-6-6 (Rec.601 NTSC)":       return ("smpte170m", "smpte170m", "smpte170m")
        case "5-6-5 (Rec.601 PAL)":        return ("bt470bg", "smpte170m", "bt470bg")

        // BT.2020 SDR/HLG/PQ
        case "9-1-9 (BT.2020 SDR)":        return ("bt2020", "bt709", "bt2020nc")
        case "9-14-9 (BT.2020 SDR BT.1361)": return ("bt2020", "bt1361", "bt2020nc")
        case "9-18-9 (BT.2020 HLG)":       return ("bt2020", "arib-std-b67", "bt2020nc")
        case "9-16-9 (BT.2020)":           return ("bt2020", "smpte2084", "bt2020nc")
        case "9-16-10 (BT.2020 PQ CL)":    return ("bt2020", "smpte2084", "bt2020c")

        // P3
        case "12-16-1 (P3-D65)":           return ("smpte432", "smpte2084", "bt709")
        case "12-13-1 (DisplayP3)":        return ("smpte432", "iec61966-2-1", "bt709")
        case "12-1-1 (P3-D65 SDR)":        return ("smpte432", "bt709", "bt709")
        case "12-18-1 (P3-D65 HLG)":       return ("smpte432", "arib-std-b67", "bt709")

        default: return nil
        }
    }
}

enum OutputNamer {
    static func suggestedOutputURL(for input: URL, settings: Settings) -> URL {
        let folder = input.deletingLastPathComponent()
        let stem   = input.deletingPathExtension().lastPathComponent
        let ext    = input.pathExtension.isEmpty ? "mov" : input.pathExtension.lowercased()

        let suffix = settings.outputSuffix.isEmpty ? "-HEVC" : settings.outputSuffix

        var out = folder.appendingPathComponent("\(stem)\(suffix)").appendingPathExtension(ext)

        var idx = 2
        while FileManager.default.fileExists(atPath: out.path) {
            out = folder.appendingPathComponent("\(stem)\(suffix)_\(idx)").appendingPathExtension(ext)
            idx += 1
        }
        return out
    }
}

