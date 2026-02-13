//
//  ValidationService.swift
//  MrEncode
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

        // --- Rule 1: Only block in Deadline mode if the SOURCE path isn't farm-visible ---
        if settings.runMode == .remoteDeadline {
            if case .failure(let error) = EncodeRenderfarm.isInputPathAcceptableForFarm(item.url) {
                item.status = .blocked
                item.statusReason = error.message
                item.isChecked = false
                return
            }
            // If pool is 'none' or empty, warn via UI elsewhere if you want — but DO NOT block here.
            // (We intentionally do nothing here so users can still queue locally or fix later.)
        }

        // --- Rule 2: Never block for naming/collision/no-op/bypass ---
        // Auto-uniquing (“_2”, “_3”, …) handles collisions.
        // Bypass (No Recompression) is a valid mode (stream copy), not a blocker.
        // NCLC “No Change” + no overlays is fine too.

        // --- Rule 3: If previously blocked for non-farm reasons, clear it now ---
        if item.status == .blocked {
            if let reason = item.statusReason, (
                reason.hasPrefix("Nothing to do!") ||
                reason.hasPrefix("Output name would match source") ||
                reason.hasPrefix("Deadline pool") ||
                reason.localizedCaseInsensitiveContains("render farm")
            ) {
                item.status = .queued
                item.statusReason = nil
                item.isChecked = true
            }
        }

        // Otherwise, leave as queued (no change).
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
            
            if reason.localizedCaseInsensitiveContains("render farm") {
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
