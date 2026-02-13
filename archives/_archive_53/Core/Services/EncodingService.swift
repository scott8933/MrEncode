//
//  EncodingService.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/23/25.
//


//
// MARK: - EncodingService.swift
//

import Foundation
import SwiftUI
import Combine

/// Coordinates encoding operations between local and remote modes
class EncodingService: ObservableObject {
    static let shared = EncodingService()
    
    private init() {}
    
    // MARK: - Process Management for Cancellation
    private static var activeProcesses: [UUID: Process] = [:]
    private static var processQueue = DispatchQueue(label: "mrencode.processes", attributes: .concurrent)
    
    /// Global pause (UI + scheduler gate); not persisted
    @Published var isGloballyPaused: Bool = false
    
    /// Submit items for encoding
    func submitItems(_ items: [MediaItem], settings: Settings, onStatusUpdate: @escaping (UUID, EncodeStatus, String?) -> Void) {
        guard !items.isEmpty else { return }
        
        // Dispatch to the selected run mode
        switch settings.runMode {
        case .localFFmpeg:
            EncodeLocal.run(items: items, settings: settings)
        case .remoteDeadline:
            EncodeRemote.run(items: items, settings: settings)
        }
    }
    
    /// Cancel all active encoding processes
    func cancelAllEncoding() {
        Self.processQueue.async(flags: .barrier) {
            for (id, process) in Self.activeProcesses {
                if process.isRunning {
                    print("🛑 Terminating process for item \(id)")
                    process.terminate()
                    
                    // Wait briefly for graceful termination
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                        if process.isRunning {
                            print("🔥 Force-killing process for item \(id)")
                            // Use SIGKILL signal for force termination
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
            }
            Self.activeProcesses.removeAll()
        }
    }
    
    /// Register a process for cancellation tracking
    static func registerProcess(_ process: Process, for itemID: UUID) {
        processQueue.async(flags: .barrier) {
            activeProcesses[itemID] = process
        }
    }
    
    /// Unregister a process (typically when encoding completes)
    static func unregisterProcess(for itemID: UUID) {
        processQueue.async(flags: .barrier) {
            activeProcesses.removeValue(forKey: itemID)
        }
    }
}
