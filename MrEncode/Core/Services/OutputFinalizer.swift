//
//  OutputFinalizer.swift
//  MrEncode
//
//  Created by scott ulrich on 2/5/26.
//


import Foundation

enum OutputFinalizer {

    struct Options {
        var allowOverwrite: Bool
    }

    static func finalize(tempURL: URL, finalURL: URL, options: Options) throws {
        let fm = FileManager.default

        // Ensure temp exists before doing anything destructive.
        guard fm.fileExists(atPath: tempURL.path) else {
            throw NSError(domain: "MrEncode", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Temp output missing at finalize: \(tempURL.path)"
            ])
        }

        let finalExists = fm.fileExists(atPath: finalURL.path)

        if finalExists {
            guard options.allowOverwrite else {
                // Don’t leave temp behind if overwrite is disallowed.
                try? fm.removeItem(at: tempURL)
                throw NSError(domain: "MrEncode", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Output exists and overwrite is disabled: \(finalURL.path)"
                ])
            }

            // Best overwrite semantics on same volume; also fine cross-volume in many cases.
            // If it fails, we fall back to explicit remove+move/copy below.
            do {
                _ = try fm.replaceItemAt(
                    finalURL,
                    withItemAt: tempURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )

                // At this point tempURL should be gone. If not, sweep defensively.
                try? fm.removeItem(at: tempURL)
                return
            } catch {
                // Fallback: remove final then attempt move/copy. (Less atomic, but reliable.)
                try? fm.removeItem(at: finalURL)
                try moveOrCopy(tempURL: tempURL, finalURL: finalURL)
                return
            }
        } else {
            // Destination does not exist: fast path move, fallback copy.
            try moveOrCopy(tempURL: tempURL, finalURL: finalURL)
            return
        }
    }

    private static func moveOrCopy(tempURL: URL, finalURL: URL) throws {
        let fm = FileManager.default
        do {
            try fm.moveItem(at: tempURL, to: finalURL)  // fast rename if same volume
            return
        } catch let err as NSError {
            // Cross-device move typically throws EXDEV (error 18).
            // Some file providers/mounts throw different codes; treat “can’t move” as a signal to copy+delete.
            if err.domain == NSPOSIXErrorDomain && err.code == 18 {
                // EXDEV: Invalid cross-device link
                try fm.copyItem(at: tempURL, to: finalURL)
                try? fm.removeItem(at: tempURL)
                return
            }

            // If it wasn't EXDEV, you can still choose to attempt copy+delete as a pragmatic fallback:
            // (Many providers don’t report EXDEV cleanly.)
            try fm.copyItem(at: tempURL, to: finalURL)
            try? fm.removeItem(at: tempURL)
        }
    }
}
