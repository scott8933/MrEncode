//
//  EncodingService.swift
//  MrEncode
//
//  Coordinates encoding operations.  Owns:
//    - Global pause / cancel state
//    - Per-item cancel handler registration (for EncodeGUI's CancelToken)
//    - The local dispatch loop (serial queue, cancel/pause gating)
//    - Route selection: local vs remote
//

import Foundation
import SwiftUI
import Combine

class EncodingService: ObservableObject {
    static let shared = EncodingService()

    private init() {}

    // MARK: - Local encode queue

    /// Serial queue — one local encode at a time.
    private static let encodeQueue = DispatchQueue(label: "mrencode.local.encode.serial")

    // MARK: - Cancel-handler registry (EncodeGUI CancelToken hooks)

    private static var activeCancelHandlers: [UUID: () -> Void] = [:]
    private static let handlerQueue = DispatchQueue(label: "mrencode.cancelhandlers", attributes: .concurrent)

    static func registerCancelHandler(for itemID: UUID, _ handler: @escaping () -> Void) {
        handlerQueue.async(flags: .barrier) {
            activeCancelHandlers[itemID] = handler
        }
    }

    static func unregisterCancelHandler(for itemID: UUID) {
        handlerQueue.async(flags: .barrier) {
            activeCancelHandlers.removeValue(forKey: itemID)
        }
    }

    // MARK: - Global pause / cancel

    /// Global pause (UI + scheduler gate); not persisted.
    @Published var isGloballyPaused: Bool = false

    /// Global cancel flag — set by Stop, cleared when a new batch starts.
    private var _wasGloballyCancelled = false
    private let cancelLock = NSLock()

    var wasGloballyCancelled: Bool {
        cancelLock.lock(); defer { cancelLock.unlock() }
        return _wasGloballyCancelled
    }

    private func setGloballyCancelled(_ value: Bool) {
        cancelLock.lock()
        _wasGloballyCancelled = value
        cancelLock.unlock()
    }

    // MARK: - Submit

    /// Entry point from AppCore.
    func submitItems(_ items: [MediaItem], settings: Settings, onStatusUpdate: @escaping (UUID, EncodeStatus, String?) -> Void) {
        guard !items.isEmpty else { return }

        // Fresh batch — clear any stale cancel from a previous Stop
        setGloballyCancelled(false)

        switch settings.runMode {
        case .localNative:
            runLocal(items: items, settings: settings)
        case .remoteDeadline:
            EncodeRenderfarm.run(items: items, settings: settings)
        }
    }

    // MARK: - Local dispatch loop

    /// Iterates items with cancel/pause gating, dispatching each onto the
    /// serial encode queue.  The actual per-item work lives in EncodeGUI.
    private func runLocal(items: [MediaItem], settings: Settings) {
        let needsOverlays = settings.burnInTimecode || settings.burnInFrames || settings.burnInFilename

        print("MODE: Local (native AVFoundation/VideoToolbox)")
        print("Quality: \(settings.qualityCRF)  Scale: \(settings.scale.rawValue)  NCLC: \(settings.nclcTag)")
        if needsOverlays && settings.codec == .bypass {
            print("  → Overlays active with bypass codec: encoding required")
        }

        for item in items {
            if wasGloballyCancelled {
                print("🛑 Global cancel detected - stopping queue")
                break
            }

            // Pause gate — poll until resumed or cancelled
            while isGloballyPaused {
                if wasGloballyCancelled {
                    print("🛑 Stop during pause - exiting")
                    break
                }
                Thread.sleep(forTimeInterval: 0.5)
            }

            if item.status == .blocked   { continue }
            if item.status == .encoding  { continue }

            Self.encodeQueue.async {
                EncodeGUI.encodeItem(item, settings: settings)
            }
        }
    }

    // MARK: - Cancel

    /// Fires all registered per-item cancel handlers and sets the global flag.
    func cancelAllEncoding() {
        setGloballyCancelled(true)

        Self.handlerQueue.async(flags: .barrier) {
            for (id, handler) in Self.activeCancelHandlers {
                print("🛑 Cancelling encode for item \(id)")
                handler()
            }
            Self.activeCancelHandlers.removeAll()
        }
    }
}
