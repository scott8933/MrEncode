//
//  EncodeGUI.swift
//  MrEncode
//
//  GUI-path encoder.  Owns: cancel-token lifecycle, AppCore status updates,
//  progress reporting, output-URL resolution, overlay rendering, and the
//  read/write pump.
//  All codec / bitrate / composition / NCLC / filtering logic delegates to EncodeCore.
//

import Foundation
import AVFoundation
import VideoToolbox

enum EncodeGUI {

    // private static let dimensionAlignment: Int = 2

    private final class CancelToken {
        private let lock = NSLock()
        private var _cancelled = false
        func cancel() { lock.lock(); _cancelled = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    }

    static func encodeItem(_ item: MediaItem, settings: Settings) {

        // Global cancel / pause checks
        if EncodingService.shared.wasGloballyCancelled {
            print("Skipping item (global cancel) - \(item.url.lastPathComponent)")
            DispatchQueue.main.async {
                if let idx = AppCore.shared.files.firstIndex(where: { $0.id == item.id }) {
                    AppCore.shared.files[idx].status = .queued
                    AppCore.shared.files[idx].statusReason = nil
                }
            }
            return
        }

        while EncodingService.shared.isGloballyPaused {
            if EncodingService.shared.wasGloballyCancelled {
                print("Stop during pause - exiting")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        // Cancel token + registration
        let token = CancelToken()
        EncodingService.registerCancelHandler(for: item.id) { token.cancel() }
        defer { EncodingService.unregisterCancelHandler(for: item.id) }

        // Mark encoding on main thread
        DispatchQueue.main.async {
            if let shared = AppState.shared,
               let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                AppCore.shared.files[idx].status = .encoding
                AppCore.shared.files[idx].statusReason = nil
                AppCore.shared.files[idx].actualEncodeSeconds = nil
                AppCore.shared.files[idx].progress = 0
                AppCore.shared.files[idx].etaSeconds = nil
                AppCore.shared.files[idx].progressMode = .none
            }
        }

        // Resolve output URL (same as before)
        let outputURL: URL = {
            if let planned = item.plannedOutputURL { return planned }
            var result: URL?
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                defer { sema.signal() }
                if let shared = AppState.shared,
                   let idx = shared.files.firstIndex(where: { $0.id == item.id }),
                   let planned = shared.files[idx].plannedOutputURL {
                    result = planned
                } else {
                    result = OutputNamer.suggestedOutputURL(for: item.url, settings: settings)
                }
            }
            sema.wait()
            return result ?? OutputNamer.suggestedOutputURL(for: item.url, settings: settings)
        }()

        let startedAt = Date()

        // Build overlay hook (GUI-only)
        let needsOverlays = settings.burnInTimecode || settings.burnInFrames || settings.burnInFilename
        let overlayHook: (@Sendable (CVPixelBuffer, FrameContext) -> Void)? = {
            guard needsOverlays else { return nil }

            // Mirror your previous overlay config, but compute aligned size inside hook lazily:
            // We need outputSize; engine already aligns, but we can reuse settings/meta to rebuild config here.
            // If you want perfect 1:1, we can pass aligned dimensions back via an event later.
            return { pb, ctx in
                // Rebuild config using engine-aligned size assumptions isn’t possible here without knowing aligned dims.
                // So instead we compute config once outside, but we need aligned dims.
                // Clean solution: compute overlay config in engine-adapter after probing track.
                // For now, we’ll draw using a config created below after we probe the track locally.
                // (See NOTE below.)
            }
        }()

        // NOTE: Overlay config needs aligned dimensions. In your old code, those came from probing the track.
        // Tight solution (no duplication): create the overlayConfig inside the engine by passing enough data,
        // or have the engine emit a "pipelineBuilt(outputSize:...)" event.
        //
        // For this step, to avoid re-probing, we’ll implement overlays by passing a hook that creates the config
        // on first call using the pixel buffer size (which equals aligned output size).
        //
        // That keeps the GUI adapter thin and avoids a second AVAsset probe.

        final class OverlayState {
            var config: OverlayRenderer.Config?
        }
        let overlayState = OverlayState()

        let frameHook: (@Sendable (CVPixelBuffer, FrameContext) -> Void)? = {
            guard needsOverlays else { return nil }
            return { pb, ctx in
                if overlayState.config == nil {
                    let w = CVPixelBufferGetWidth(pb)
                    let h = CVPixelBufferGetHeight(pb)
                    overlayState.config = OverlayRenderer.Config(
                        outputSize: CGSize(width: w, height: h),
                        fps: ctx.nominalFPS,
                        startTimecode: item.meta.startTimecode,
                        filename: item.url.lastPathComponent,
                        settings: settings
                    )
                }
                if let cfg = overlayState.config {
                    OverlayRenderer.drawOverlays(on: pb, frameNumber: ctx.frameIndex, config: cfg)
                }
            }
        }()

        // Event sink: map engine events → AppCore (GUI)
        let emit: EncodeEventSink = { ev in
            switch ev {
            case .phase:
                break

            case .warning(let s):
                DispatchQueue.main.async {
                    AppState.shared?.pushMessage(level: .warning, s, filename: item.url.lastPathComponent)
                }

            case .progress(let pr):
                DispatchQueue.main.async {
                    if let idx = AppCore.shared.files.firstIndex(where: { $0.id == item.id }) {
                        AppCore.shared.files[idx].progress = pr.fraction
                        AppCore.shared.files[idx].etaSeconds = pr.etaSeconds
                    }
                }

            case .completed:
                let finishedAt = Date()
                DispatchQueue.main.async {
                    AppCore.shared.localEncodeDidComplete(
                        itemID: item.id,
                        outputURL: outputURL,
                        errorText: nil,
                        encodeSeconds: finishedAt.timeIntervalSince(startedAt)
                    )

                    let secs = Int(round(finishedAt.timeIntervalSince(startedAt)))
                    AppState.shared?.pushMessage(
                        level: .info,
                        "Local encode complete (\(secs / 60)m \(String(format: "%02d", secs % 60))s)",
                        filename: item.url.lastPathComponent
                    )
                }

            case .failed(let e):
                // Engine already cleaned temp. Match your cancelled UX vs error UX
                if e.code == .cancelled {
                    DispatchQueue.main.async {
                        if let idx = AppCore.shared.files.firstIndex(where: { $0.id == item.id }) {
                            AppCore.shared.files[idx].status = .queued
                            AppCore.shared.files[idx].statusReason = "Encode cancelled"
                            AppCore.shared.files[idx].progress = nil
                            AppCore.shared.files[idx].etaSeconds = nil
                            AppCore.shared.files[idx].progressMode = .none
                            AppCore.shared.files[idx].isChecked = false
                            AppState.shared?.pushMessage(level: .info, "Local encode cancelled",
                                                         filename: item.url.lastPathComponent)
                        }
                    }
                } else {
                    fail(itemID: item.id, reason: e.message)
                }
            }
        }

        // Run engine
        let request = EncodeRequest(
            inputURL: item.url,
            outputURL: outputURL,
            allowOverwrite: item.allowOverwrite,
            settings: settings,
            meta: item.meta,
            filenameForOverlay: item.url.lastPathComponent,
            videoFrameHook: frameHook
        )

        _ = EncodeEngine.encode(
            request,
            cancel: { token.isCancelled },
            emit: emit
        )
    }


    // MARK: - Private helpers (GUI-lifecycle only)

    private static func fail(itemID: UUID, reason: String) {
        DispatchQueue.main.async {
            if let idx = AppCore.shared.files.firstIndex(where: { $0.id == itemID }) {
                AppCore.shared.files[idx].status       = .error
                AppCore.shared.files[idx].statusReason = reason
            }
        }
    }
}
