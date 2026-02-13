//
//  QueueViewModel.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/23/25.
//


//
// MARK: - QueueViewModel.swift
//

import Foundation
import SwiftUI
import Combine

/// Handles queue-specific UI logic and formatting
class QueueViewModel: ObservableObject {
    private let core = AppCore.shared
    private let fileService = FileManagementService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Subscribe to core changes
        core.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }
    
    // MARK: - Queue Item Display Logic
    
    /// Get formatted source line for display
    func sourceDisplayText(for item: MediaItem) -> String {
        // Use cached version if available
        if let cached = item.cachedSrcLine {
            return cached
        }
        
        // Fallback to building on demand
        return fileService.buildCachedSrcLine(for: item)
    }
    
    /// Get formatted destination line for display
    func destinationDisplayText(for item: MediaItem, settings: Settings) -> String {
        // Use cached version if available
        if let cached = item.cachedDstLine {
            return cached
        }
        
        // Fallback to building on demand
        return fileService.buildCachedDstLine(for: item, settings: settings, runMode: settings.runMode)
    }
    
    /// Get status color for item
    func statusColor(for status: EncodeStatus) -> Color {
        switch status {
        case .queued: return .primary
        case .encoding: return .blue
        case .done: return .green
        case .error: return .red
        case .blocked: return .orange
        }
    }
    
    /// Get status icon for item
    func statusIcon(for status: EncodeStatus) -> String {
        switch status {
        case .queued: return "circle"
        case .encoding: return "gear"
        case .done: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .blocked: return "exclamationmark.circle.fill"
        }
    }
    
    /// Get progress display info
    func progressInfo(for item: MediaItem) -> (showProgress: Bool, progress: Double, text: String?) {
        switch item.progressMode {
        case .none:
            return (false, 0, nil)
        case .fake:
            return (true, 0, item.statusReason)
        case .real:
            let progress = item.progress ?? 0
            var text: String?
            if let eta = item.etaSeconds, eta > 0 {
                let mins = Int(eta / 60)
                let secs = Int(eta.truncatingRemainder(dividingBy: 60))
                text = String(format: "%d:%02d remaining", mins, secs)
            }
            return (true, progress, text)
        }
    }
    
    /// Check if item can be removed
    func canRemoveItem(_ item: MediaItem) -> Bool {
        return item.status != .encoding
    }
    
    /// Check if item can be toggled
    func canToggleItem(_ item: MediaItem) -> Bool {
        return item.status != .encoding
    }
    
    /// Get tooltip text for status
    func statusTooltip(for item: MediaItem) -> String {
        var parts: [String] = []
        
        // Status
        parts.append("Status: \(item.status.rawValue.capitalized)")
        
        // Reason if blocked/error
        if let reason = item.statusReason, !reason.isEmpty {
            parts.append("Reason: \(reason)")
        }
        
        // Output path if available
        if let outputURL = item.finalOutputURL {
            parts.append("Output: \(outputURL.lastPathComponent)")
        }
        
        return parts.joined(separator: "\n")
    }
}

