//
//  FooterViewModel.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/23/25.
//


//
// MARK: - FooterViewModel.swift
//

import Foundation
import SwiftUI
import Combine

/// Handles footer-specific UI logic and status formatting
class FooterViewModel: ObservableObject {
    private let core = AppCore.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Subscribe to core changes
        core.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }
    
    // MARK: - Status Display Logic
    
    func formatStatusLine(files: [MediaItem], hasSelection: Bool, runMode: RunMode) -> String {
        let targetFiles = hasSelection ? 
            files.filter { file in files.contains { $0.id == file.id } } : 
            files
            
        let queued = targetFiles.filter { $0.status == .queued && $0.isChecked }.count
        let encoding = targetFiles.filter { $0.status == .encoding }.count
        let done = targetFiles.filter { $0.status == .done }.count
        let blocked = targetFiles.filter { $0.status == .blocked }.count
        let errors = targetFiles.filter { $0.status == .error }.count
        
        var parts: [String] = []
        
        if encoding > 0 {
            let verb = runMode == .localFFmpeg ? "encoding" : "submitted"
            parts.append("\(encoding) \(verb)")
        }
        
        if queued > 0 {
            parts.append("\(queued) queued")
        }
        
        if done > 0 {
            parts.append("\(done) done")
        }
        
        if blocked > 0 {
            parts.append("\(blocked) blocked")
        }
        
        if errors > 0 {
            parts.append("\(errors) errors")
        }
        
        if parts.isEmpty {
            return "Ready"
        }
        
        return parts.joined(separator: " • ")
    }
    
    // MARK: - Time Estimate Logic
    
    func formatTimeEstimate(files: [MediaItem], hasSelection: Bool, settings: Settings) -> String? {
        let targetFiles = hasSelection ? 
            files.filter { file in files.contains { $0.id == file.id } } : 
            files
            
        let queuedAndChecked = targetFiles.filter { $0.status == .queued && $0.isChecked }
        
        guard !queuedAndChecked.isEmpty else { return nil }
        
        var totalSeconds: Double = 0
        var itemCount = 0
        
        for item in queuedAndChecked {
            if let estimate = EncodeTimeEstimator.estimateSeconds(
                url: item.url,
                meta: item.meta,
                settings: settings,
                runMode: settings.runMode
            ), estimate.isFinite, estimate > 0 {
                totalSeconds += estimate
                itemCount += 1
            }
        }
        
        guard itemCount > 0 else { return nil }
        
        let formatted = core.formatHMS(totalSeconds)
        return "Est. Total: \(formatted)"
    }
    
    // MARK: - Progress Logic
    
    func shouldShowProgress(files: [MediaItem]) -> Bool {
        return files.contains { $0.status == .encoding }
    }
    
    func globalProgress(files: [MediaItem]) -> Double {
        let activeItems = files.filter { $0.status == .encoding }
        guard !activeItems.isEmpty else { return 0.0 }
        
        let progressValues = activeItems.compactMap { $0.progress }
        guard !progressValues.isEmpty else { return 0.0 }
        
        return progressValues.reduce(0.0, +) / Double(progressValues.count)
    }
    
    // MARK: - Message Logic
    
    func shouldShowMessages(_ messages: [AppLogEntry]) -> Bool {
        return messages.contains { !$0.acknowledged }
    }
    
    func unacknowledgedMessages(_ messages: [AppLogEntry]) -> [AppLogEntry] {
        return messages.filter { !$0.acknowledged }
    }
    
    func messageIcon(for level: LogLevel) -> String {
        switch level {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "exclamationmark.circle"
        }
    }
    
    func messageColor(for level: LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange  
        case .error: return .red
        }
    }
}
