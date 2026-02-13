//
//  Untitled.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/10/25.
//

// =============================
// File: EncodeRemote+Compat.swift
// =============================

import Foundation

extension EncodeRemote {

    /// Legacy wrapper expected by AppState: check if a path is render-farm friendly.
    /// Returns (ok, reason) where `reason` is a short, user-facing string on failure.
    static func isInputPathAcceptableForFarm(_ url: URL) -> (ok: Bool, reason: String?) {
        return checkPathFarmSuitability(url.path)
    }

    /// Legacy helper expected by AppState: fetch Pools and Groups via `deadlinecommand`.
    /// Adjust flags if your Deadline version uses different names.
    static func fetchLists(deadlineCmd: String) throws -> Lists {
        let pools  = try runAndCollect(deadlineCmd, ["-GetPoolNames"])
        let groups = try runAndCollect(deadlineCmd, ["-GetGroupNames"])
        return Lists(pools: pools, groups: groups)
    }

    // MARK: - Local utility

    /// Run a CLI and return non-empty, trimmed lines; throw on non-zero exit.
    private static func runAndCollect(_ cmd: String, _ args: [String]) throws -> [String] {
        let (code, out) = runCLI(path: cmd, args: args)
        if code != 0 {
            throw NSError(
                domain: "Deadline",
                code: Int(code),
                userInfo: [NSLocalizedDescriptionKey:
                           out.isEmpty ? "deadlinecommand failed with code \(code)." : out]
            )
        }
        return out
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
