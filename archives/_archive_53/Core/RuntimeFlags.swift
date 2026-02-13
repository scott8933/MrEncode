//
//  RuntimeFlags.swift
//  MrEncode
//
//  Created by scott ulrich on 1/24/26.
//


import Foundation

struct RuntimeFlags {
    let suppressChime: Bool
    let quiet: Bool

    static var current: RuntimeFlags {
        parse(CommandLine.arguments)
    }

    static func parse(_ arguments: [String]) -> RuntimeFlags {
        let lowered = Set(arguments.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        let muteFlags: Set<String> = [
            "--no-chime", "--nochime", "-nochime",
            "--no-sound", "--nosound", "-nosound",
            "--no-audio", "--noaudio", "-noaudio",
            "--mute", "-mute"
        ]

        let quietFlags: Set<String> = ["--quiet", "-quiet", "--silent", "-silent"]

        return RuntimeFlags(
            suppressChime: !lowered.intersection(muteFlags).isEmpty,
            quiet: !lowered.intersection(quietFlags).isEmpty
        )
    }
}

extension RuntimeFlags {
    /// CLI flags that consume the NEXT argument as a value.
    /// Centralized so callers don't re-enumerate these.
    static let flagsWithValue: Set<String> = [
        "--preset-file",
        "--droplet",
        "--droplet-debug-log"
    ]

    /// Optional: a canonical set of known boolean flags (if you want to treat them specially).
    static let booleanFlags: Set<String> = [
        "--cli",
        "--help", "-h",
        "--quiet", "-quiet", "--silent", "-silent",
        "--no-chime", "--nochime", "-nochime",
        "--no-sound", "--nosound", "-nosound",
        "--no-audio", "--noaudio", "-noaudio",
        "--mute", "-mute"
    ]
}
