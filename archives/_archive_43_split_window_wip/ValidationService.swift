//
//  ValidationService.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/23/25.
//


//
// MARK: - ValidationService.swift
//

import Foundation
import SwiftUI

/// Handles file validation and status checking
class ValidationService {
    static let shared = ValidationService()
    
    private init() {}
    
    /// Validate a single item against current settings
    func validateItem(_ item: inout MediaItem, settings: Settings) {
        // Leave active/finished rows alone
        switch item.status {
        case .encoding, .done:
            return
        default:
            break
        }

        // 1) Remote path gating (only matters in Remote mode)
        var newReason: String? = nil
        var newCat: LogCode? = nil

        if settings.runMode == .remoteDeadline {
            let okFarm = EncodeRemote.isInputPathAcceptableForFarm(item.url)
            if !okFarm.ok {
                newReason = okFarm.reason ?? "Not accessible to render farm."
                newCat = .farmPath
            }
            else {
                let poolCheck = settings.pool.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if poolCheck.isEmpty || poolCheck == "none" {
                    newReason = "Deadline pool is 'none' - jobs will not start."
                    newCat = .other  // ← USE .other INSTEAD
                }
            }
        }

        // 2) "Nothing to do" check
        if newReason == nil {
            let compressionInactive = settings.bypassHEVC &&
                                     settings.scale == .oneToOne &&
                                     settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            let nclcInactive = settings.nclcTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "no change" &&
                              settings.nclcFilenameLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            let overlaysInactive = !(settings.burnInFrames || settings.burnInTimecode || settings.burnInFilename)

            if compressionInactive && nclcInactive && overlaysInactive {
                newReason = "Nothing to do!"
                newCat = .noOp
            }
        }

        // 3) Output overwrite check
        if newReason == nil && settings.bothSuffixesBlank {
            newReason = "Output name would match source. Add a suffix in NCLC Settings or Compression & Resizing."
            newCat = .wouldOverwrite
        }

        // Apply validation results
        if let reason = newReason {
            item.status = .blocked
            item.statusReason = reason
            item.isChecked = false
        } else if item.status == .blocked {
            // Previously blocked but now safe, unblock
            if let reason = item.statusReason,
               reason.hasPrefix("Nothing to do!") || 
               reason.hasPrefix("Output name would match source") ||
               reason.hasPrefix("Not accessible") ||
               reason.hasPrefix("Deadline pool") {
                item.status = .queued
                item.statusReason = nil
            }
        }
    }
    
    /// Check all validation categories for current state
    func getValidationSummary(for files: [MediaItem], settings: Settings) -> (
        anyFarmBlocked: Bool,
        anyNoOpBlocked: Bool,
        anyOverwriteBlocked: Bool,
        anyPoolBlocked: Bool
    ) {
        var anyFarmBlocked = false
        var anyNoOpBlocked = false
        var anyOverwriteBlocked = false
        var anyPoolBlocked = false
        
        for item in files {
            guard let reason = item.statusReason else { continue }
            
            if reason.contains("Not accessible") {
                anyFarmBlocked = true
            } else if reason.contains("Nothing to do") {
                anyNoOpBlocked = true
            } else if reason.contains("Output name would match source") {
                anyOverwriteBlocked = true
            } else if reason.contains("pool is 'none'") {  // ← Check by message text instead
                anyPoolBlocked = true
            }
        }
        
        return (anyFarmBlocked, anyNoOpBlocked, anyOverwriteBlocked, anyPoolBlocked)
    }}
