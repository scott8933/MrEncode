//
//  NCLCMap.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/10/25.
//


// =============================
// File: NCLCMap.swift
// =============================
import Foundation

enum NCLCMap {
    struct Triplet { let primaries: String; let trc: String; let matrix: String }

    // Canonical labels (match UI)
    static let noChange = "No Change"

    // Minimal table; extend as needed.
    private static let table: [String: Triplet] = [
        "1-1-1 (BT.709)"        : .init(primaries: "1",  trc: "1",  matrix: "1"),
        "1-13-1 (sRGB)"         : .init(primaries: "1",  trc: "13", matrix: "1"),
        "9-16-9 (BT.2020)"      : .init(primaries: "9",  trc: "16", matrix: "9"),
        "12-16-1 (P3-D65)"      : .init(primaries: "12", trc: "16", matrix: "1"),
        "12-13-1 (DisplayP3)"   : .init(primaries: "12", trc: "13", matrix: "1"),
        "6-6-6 (Rec.601 NTSC)"  : .init(primaries: "6",  trc: "6",  matrix: "6"),
        "5-6-5 (Rec.601 PAL)"   : .init(primaries: "5",  trc: "6",  matrix: "5"),
        "9-1-9 (BT.2020 SDR)"   : .init(primaries: "9",  trc: "1",  matrix: "9"),
        "9-14-9 (BT.2020 SDR BT.1361)": .init(primaries: "9", trc: "14", matrix: "9"),
        "12-1-1 (P3-D65 SDR)"   : .init(primaries: "12", trc: "1",  matrix: "1"),
        "12-18-1 (P3-D65 HLG)"  : .init(primaries: "12", trc: "18", matrix: "1"),
        "9-18-9 (BT.2020 HLG)"  : .init(primaries: "9",  trc: "18", matrix: "9"),
        "9-16-10 (BT.2020 PQ CL)": .init(primaries: "9", trc: "16", matrix: "10"),
        "1-4-1 (BT.709 γ2.2)"   : .init(primaries: "1",  trc: "4",  matrix: "1"),
        "1-5-1 (BT.709 γ2.8)"   : .init(primaries: "1",  trc: "5",  matrix: "1")
    ]

    static func lookup(labelOrCode: String) -> Triplet? {
        if labelOrCode == noChange { return nil }
        // First try full label:
        if let t = table[labelOrCode] { return t }
        // Next, try "p-t-m" numeric
        let s = labelOrCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = s.split(separator: "-").map { String($0) }
        if parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) {
            return .init(primaries: parts[0], trc: parts[1], matrix: parts[2])
        }
        return nil
    }
}
