//
//  CompressorTagger.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/11/25.
//


import Foundation
import AVFoundation

enum CompressorTagger {
    struct Triplet { let p: String, t: String, m: String }

    /// Returns true if Compressor.app’s CLI is available.
    static func isAvailable() -> Bool {
        FileManager.default.isExecutableFile(atPath: "/Applications/Compressor.app/Contents/MacOS/Compressor")
    }

    /// Fast in-place relabel using Compressor. Throws on non-zero exit.
    static func relabelInPlace(file url: URL, triplet: Triplet) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/Applications/Compressor.app/Contents/MacOS/Compressor")
        proc.arguments = ["-jobpath", url.path, "-relabelcolorspace", triplet.p, triplet.t, triplet.m]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let err  = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "CompressorTagger", code: Int(proc.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Compressor relabel failed: \(err)"])
        }
    }

    /// Decide if conditions qualify for in-place tag only, and execute if possible.
    /// Returns true if handled (i.e., ffmpeg should be skipped).
    static func tryTagOnlyIfEligible(input: URL,
                                     output: URL,
                                     settings: Settings,
                                     meta: MediaMetadata,
                                     log: (String) -> Void) -> Bool
    {
        // Conditions: Local mode, bypass on, no scaling, no overlays, have triplet, compressor present.
        guard settings.runMode == .localFFmpeg,
              settings.bypassHEVC,
              settings.scale == .oneToOne,
              !(settings.burnInFrames || settings.burnInTimecode || settings.burnInFilename),
              let trip = buildTriplet(from: settings, meta: meta),
              isAvailable()
        else { return false }

        do {
            // If output path differs, copy once so we “edit in place” on the output.
            let target: URL
            if input.standardizedFileURL != output.standardizedFileURL {
                try? FileManager.default.removeItem(at: output)
                try FileManager.default.copyItem(at: input, to: output)
                target = output
            } else {
                target = input
            }

            try relabelInPlace(file: target, triplet: trip)
            log("Tagged NCLC \(trip.p)-\(trip.t)-\(trip.m) via Compressor (in-place).")
            return true
        } catch {
            log("Compressor tag failed, falling back to ffmpeg copy: \(error.localizedDescription)")
            return false
        }
    }

    /// Build numeric triplet from Settings or metadata.
    /// - If user chose "No Change": require meta to have numeric strings (already normalized by MetadataExtractor).
    /// - If user picked a specific label like "1-1-1 (BT.709)": parse first token "1-1-1".
    private static func buildTriplet(from settings: Settings, meta: MediaMetadata) -> Triplet? {
        let tag = settings.nclcTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if tag.lowercased() == "no change" {
            guard let p = meta.colorPrimaries, let t = meta.transferFunction, let m = meta.ycbcrMatrix,
                  !p.isEmpty, !t.isEmpty, !m.isEmpty else { return nil }
            return .init(p: p, t: t, m: m)
        }

        if let first = tag.split(separator: " ").first, first.contains("-") {
            let nums = first.split(separator: "-").map(String.init)
            guard nums.count == 3, !nums[0].isEmpty, !nums[1].isEmpty, !nums[2].isEmpty else { return nil }
            return .init(p: nums[0], t: nums[1], m: nums[2])
        }

        // Fallback: cannot infer
        return nil
    }
}
