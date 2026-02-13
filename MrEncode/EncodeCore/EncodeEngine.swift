//
//  EncodeEngine.swift
//  MrEncode
//
//  Created by scott ulrich on 2/2/26.
//

import Foundation
import AVFoundation
import VideoToolbox
import CoreGraphics
import Metal
import CoreVideo

struct FrameContext: Sendable {
    public let frameIndex: Int64
    public let presentationTime: CMTime
    public let nominalFPS: Double
}

struct EncodeRequest: Sendable {
    let inputURL: URL
    let outputURL: URL
    let allowOverwrite: Bool
    let settings: Settings
    let meta: MediaMetadata
    let filenameForOverlay: String
    let videoFrameHook: (@Sendable (CVPixelBuffer, FrameContext) -> Void)?

    init(
        inputURL: URL,
        outputURL: URL,
        allowOverwrite: Bool,
        settings: Settings,
        meta: MediaMetadata,
        filenameForOverlay: String,
        videoFrameHook: (@Sendable (CVPixelBuffer, FrameContext) -> Void)? = nil
    ) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.allowOverwrite = allowOverwrite
        self.settings = settings
        self.meta = meta
        self.filenameForOverlay = filenameForOverlay
        self.videoFrameHook = videoFrameHook
    }
}

enum EncodeEngine {

    @inline(__always)
    private static func LOG(_ s: String) {
        fputs(s + "\n", stderr)
    }

    public static func encode(
        _ req: EncodeRequest,
        cancel: @escaping CancelCheck,
        emit: @escaping EncodeEventSink
    ) -> Result<EncodeResult, EncodeError> {

        
        LOG("🧪 EncodeEngine 422 TEST BUILD ACTIVE (checkpoint A)")
        
        
        emit(.phase(.preparing))

        // Resolve temp URL inside engine (shared behavior for GUI + CLI)
        let tempURL: URL
        do {
            tempURL = try TempOutputStrategy.makeTempURL(for: req.outputURL)
        } catch {
            let e = EncodeError(.unknown, "Unable to resolve temp output URL: \(error)")
            emit(.failed(e))
            return .failure(e)
        }

        // Ensure output dir exists
        do {
            try FileManager.default.createDirectory(
                at: req.outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            let e = EncodeError(.finalizeFailed, "Cannot create output folder: \(error.localizedDescription)")
            emit(.failed(e))
            return .failure(e)
        }

        emit(.phase(.probingSource))

        let needsOverlays = req.settings.burnInTimecode || req.settings.burnInFrames || req.settings.burnInFilename
        let asset = AVAsset(url: req.inputURL)

        guard let videoTrack = asset.tracks(withMediaType: AVMediaType.video).first else {
            let e = EncodeError(.invalidInput, "No video track found.")
            emit(.failed(e))
            return .failure(e)
        }

        let durationSeconds = req.meta.durationSeconds
        let frameDur = EncodeCore.snappedFrameDuration(for: videoTrack)
        let fps = EncodeCore.snappedFPS(for: videoTrack)

        let target  = EncodeCore.computeTargetDimensions(videoTrack: videoTrack, settings: req.settings)
        let aligned = EncodeCore.alignDimensions(target, alignment: 2)

        emit(.phase(.buildingPipeline))

        // Reader
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            let e = EncodeError(.readerFailed, "Reader init failed: \(error.localizedDescription)")
            emit(.failed(e))
            return .failure(e)
        }

        let videoComposition = EncodeCore.makeVideoComposition(
            track: videoTrack,
            contentSize: target,
            renderSize: aligned,
            settings: req.settings
        )

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.videoComposition = videoComposition
        videoOutput.alwaysCopiesSampleData = false

        guard reader.canAdd(videoOutput) else {
            let e = EncodeError(.pipelineFailed, "Cannot add video output to reader.")
            emit(.failed(e))
            return .failure(e)
        }
        reader.add(videoOutput)

        // Audio reader
        let audioTrack = asset.tracks(withMediaType: AVMediaType.audio).first
        var audioOutput: AVAssetReaderOutput?
        if let at = audioTrack {
            let ao = AVAssetReaderTrackOutput(track: at, outputSettings: EncodeCore.audioReaderSettings)
            ao.alwaysCopiesSampleData = false
            if reader.canAdd(ao) {
                reader.add(ao)
                audioOutput = ao
            }
        }

        // Writer
        let writer: AVAssetWriter
        do {
            let fileType: AVFileType = (req.settings.containerFormat == .mp4) ? .mp4 : .mov
            writer = try AVAssetWriter(outputURL: tempURL, fileType: fileType)
            LOG("🧪 checkpoint 1: tempURL resolved = \(tempURL.path)")
        } catch {
            let e = EncodeError(.writerFailed, "Writer init failed: \(error.localizedDescription)")
            emit(.failed(e))
            return .failure(e)
        }

        writer.movieTimeScale = (frameDur.timescale > 1000) ? frameDur.timescale : CMTimeScale(60000)
        writer.shouldOptimizeForNetworkUse = true

        // --- EncodeEngine.swift (snippet replacement) ---------------------------------
        // Drop this into your existing EncodeEngine.swift in the same spot where you
        // currently build `vidSettings` and `videoInput`.
        // This is hardwired for the 4:2:2 test build: HEVC Main42210 + P210 adaptor,
        // and it explicitly tags limited range when possible.

        var vidSettings = EncodeCore.videoInputSettings(
            settings: req.settings,
            width: aligned.width,
            height: aligned.height,
            fps: fps
        )

        // NCLC (primaries/transfer/matrix) as you already do
        if let triplet = EncodeCore.nclcTripletToApply(settings: req.settings, meta: req.meta) {
            var props = EncodeCore.nclcToAVVideoColorProperties(triplet: triplet)
            vidSettings[AVVideoColorPropertiesKey] = props
        }

        LOG("🧪 179()")

        // TEST BUILD: force HEVC Main42210 profile regardless of Settings.
        vidSettings[AVVideoCodecKey] = AVVideoCodecType.hevc.rawValue

        // Ensure compression props exists and hardwire the profile level.
        var compProps = (vidSettings[AVVideoCompressionPropertiesKey] as? [String: Any]) ?? [:]
        compProps[kVTCompressionPropertyKey_ProfileLevel as String] = (kVTProfileLevel_HEVC_Main42210_AutoLevel as String)
        vidSettings[AVVideoCompressionPropertiesKey] = compProps

        // Build writer input using the forced settings
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: vidSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.mediaTimeScale = frameDur.timescale
        videoInput.transform = .identity

        // TEST BUILD: adaptor is hardwired to P210 (4:2:2 10-bit bi-planar, video-range)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange,
                kCVPixelBufferWidthKey  as String: aligned.width,
                kCVPixelBufferHeightKey as String: aligned.height,
                // Helpful for Metal interop; harmless if ignored.
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )

        LOG("🧪 191()")
        /*
        let videoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: vidSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.mediaTimeScale = frameDur.timescale
        videoInput.transform = CGAffineTransform.identity

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                // TEST BUILD: hardwired P210 (4:2:2 10-bit bi-planar, video range)
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange,
                kCVPixelBufferWidthKey  as String: aligned.width,
                kCVPixelBufferHeightKey as String: aligned.height
            ]
        )
        LOG("🧪 206)")
*/
        // TEST BUILD: hardwired 4:2:2 10-bit converter (BGRA -> P210). No fallback.
        guard let metalConverter = Metal42210Converter() else {
            LOG("❌ Metal42210Converter init failed (returned nil)")
            let e = EncodeError(.pipelineFailed, "Metal42210Converter init failed (Metal device/library/kernel missing).")
            emit(.failed(e))
            return .failure(e)
        }
        LOG("🧪 214()")

        LOG("🧪 214()")
        guard writer.canAdd(videoInput) else {
            let e = EncodeError(.pipelineFailed, "Cannot add video input to writer.")
            emit(.failed(e))
            return .failure(e)
        }
        writer.add(videoInput)
        LOG("🧪 221()")
        // Audio input
        var audioInput: AVAssetWriterInput?
        if audioTrack != nil {
            let ai = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: EncodeCore.audioOutputSettings)
            ai.expectsMediaDataInRealTime = false
            if writer.canAdd(ai) {
                writer.add(ai)
                audioInput = ai
            }
        }
        LOG("🧪 232()")
        // Start I/O
        guard writer.startWriting() else {
            let e = EncodeError(.writerFailed, "Writer start failed: \(writer.error?.localizedDescription ?? "Unknown")")
            emit(.failed(e))
            return .failure(e)
        }
        LOG("🧪 239()")
        // ✅ put it HERE (only runs if startWriting succeeded)
        LOG("🧪 checkpoint B: startWriting returned true")
        LOG("   writer.status=\(writer.status.rawValue) (\(writer.status)) err=\(writer.error?.localizedDescription ?? "nil")")
        LOG("   adaptor.pixelBufferPool is \(adaptor.pixelBufferPool == nil ? "NIL" : "NON-NIL")")



        guard reader.startReading() else {
            let e = EncodeError(.readerFailed, "Reader start failed: \(reader.error?.localizedDescription ?? "Unknown")")
            emit(.failed(e))
            return .failure(e)
        }
        LOG("✅ reader.startReading() ok")
        LOG("   reader.status=\(reader.status.rawValue) (\(reader.status)) err=\(reader.error?.localizedDescription ?? "nil")")

        writer.startSession(atSourceTime: .zero)
        LOG("🧪 checkpoint C: startSession called")
        LOG("   writer.status=\(writer.status.rawValue) (\(writer.status)) err=\(writer.error?.localizedDescription ?? "nil")")
        LOG("   adaptor.pixelBufferPool is \(adaptor.pixelBufferPool == nil ? "NIL" : "NON-NIL")")



        emit(.phase(.encodingVideo))
        if audioOutput != nil && audioInput != nil {
            emit(.phase(.encodingAudio))
        }

        // Shared completion + failure state
        let failLock = NSLock()
        var didFail = false
        func setFailed() {
            failLock.lock(); didFail = true; failLock.unlock()
        }
        func getFailed() -> Bool {
            failLock.lock(); defer { failLock.unlock() }
            return didFail
        }

        // Progress throttle state
        let progressLock = NSLock()
        var lastEmitWall = Date().timeIntervalSinceReferenceDate
        var lastEmitFrame: Int64 = 0
        var lastEmitPTS: CMTime = .zero
        var encodedFrames: Int64 = 0

        func maybeEmitProgress(currentFrame: Int64, outPTS: CMTime) {
            guard durationSeconds > 0 else { return }

            let now = Date().timeIntervalSinceReferenceDate

            progressLock.lock()
            defer { progressLock.unlock() }

            // Throttle: emit at most every 0.25s OR every 12 frames
            let wallDelta = now - lastEmitWall
            let frameDelta = currentFrame - lastEmitFrame
            if wallDelta < 0.25 && frameDelta < 12 { return }

            let secondsDone = CMTimeGetSeconds(outPTS)
            let frac = min(max(secondsDone / durationSeconds, 0.0), 1.0)

            // Rolling fps estimate based on pts delta (better for odd timebases)
            let ptsDelta = CMTimeSubtract(outPTS, lastEmitPTS)
            let secDelta = max(0.0001, CMTimeGetSeconds(ptsDelta))
            let fpsEst = Double(frameDelta) / secDelta

            let eta = (frac > 0.0001) ? (durationSeconds - secondsDone) : nil

            lastEmitWall = now
            lastEmitFrame = currentFrame
            lastEmitPTS = outPTS

            emit(.progress(.init(
                fraction: frac,
                framesDone: Int(currentFrame),
                framesTotal: nil,
                secondsDone: secondsDone,
                secondsTotal: durationSeconds,
                fps: fpsEst.isFinite ? fpsEst : nil,
                etaSeconds: eta,
                bytesWritten: nil,
                message: "Encoding..."
            )))
        }

        let group = DispatchGroup()
        let videoQueue = DispatchQueue(label: "mrencode.engine.video", qos: .userInitiated)
        let audioQueue = DispatchQueue(label: "mrencode.engine.audio", qos: .userInitiated)

        // Ensure group.leave is called once per pump
        let videoDoneLock = NSLock()
        var videoDone = false
        func finishVideoPump() {
            videoDoneLock.lock()
            defer { videoDoneLock.unlock() }
            if videoDone { return }
            videoDone = true
            videoInput.markAsFinished()
            group.leave()
        }

        let audioDoneLock = NSLock()
        var audioDone = false
        func finishAudioPump(_ input: AVAssetWriterInput) {
            audioDoneLock.lock()
            defer { audioDoneLock.unlock() }
            if audioDone { return }
            audioDone = true
            input.markAsFinished()
            group.leave()
        }

        // VIDEO pump

        // TEST BUILD: 4:2:2 hardwired (no vImage / no CPU fallback)
        group.enter()
        var frameIndex: Int64 = 0

        videoInput.requestMediaDataWhenReady(on: videoQueue) {
            while videoInput.isReadyForMoreMediaData {

                if cancel() { finishVideoPump(); return }

                guard let sb = videoOutput.copyNextSampleBuffer() else {
                    finishVideoPump(); return
                }

                guard let srcPB = CMSampleBufferGetImageBuffer(sb) else {
                    setFailed(); finishVideoPump(); return
                }

                if cancel() { finishVideoPump(); return }

                // Optional GUI overlay / effects hook (operate on BGRA source buffer)
                if needsOverlays, let hook = req.videoFrameHook {
                    let ctx = FrameContext(frameIndex: frameIndex, presentationTime: sb.presentationTimeStamp, nominalFPS: fps)
                    hook(srcPB, ctx)
                }

                // Perceptual conditioning (still operating on source buffer)
                if Double(req.settings.qualityCRF) <= 20.0 {
                    EncodeCore.applyChromaSmoothing(to: srcPB, radius: 0.6)
                }

                // TEST BUILD: 4:2:2 hardwired.
                // Always convert BGRA -> P210 (422 10-bit bi-planar) into the adaptor pool.
                // No CPU fallback and no source-buffer append.
                guard let pool = adaptor.pixelBufferPool else {
                    LOG("❌ adaptor.pixelBufferPool == nil AT FIRST USE")
                    LOG("   writer.status=\(writer.status.rawValue) (\(writer.status)) err=\(writer.error?.localizedDescription ?? "nil")")
                    LOG("   videoInput.isReadyForMoreMediaData=\(videoInput.isReadyForMoreMediaData)")
                    setFailed()
                    finishVideoPump()
                    return
                }


                var dst: CVPixelBuffer?
                if CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &dst) != kCVReturnSuccess || dst == nil {
                    LOG("❌ CVPixelBufferPoolCreatePixelBuffer failed (P210)")
                    LOG("   writer.status=\(writer.status.rawValue) (\(writer.status)) err=\(writer.error?.localizedDescription ?? "nil")")
                    setFailed(); finishVideoPump(); return
                }
                let dstPB = dst!

                if !metalConverter.convert(srcPB: srcPB, dstPB: dstPB) {
                    LOG("❌ Metal42210Converter.convert failed")
                    setFailed(); finishVideoPump(); return
                }

                let encPB: CVPixelBuffer = dstPB

                // NCLC per-frame (apply to the buffer that will be encoded)
                if let triplet = EncodeCore.nclcTripletToApply(settings: req.settings, meta: req.meta) {
                    EncodeCore.applyNCLCToPixelBuffer(encPB, triplet: triplet)
                }

                let outPTS = CMTimeMultiply(frameDur, multiplier: Int32(frameIndex))
                frameIndex += 1
                encodedFrames = frameIndex

                maybeEmitProgress(currentFrame: frameIndex, outPTS: outPTS)

                if cancel() { finishVideoPump(); return }

                LOG("➡️ about to append frame @ pts=\(outPTS)")
                let ok = adaptor.append(encPB, withPresentationTime: outPTS)
                if !ok {
                    LOG("❌ pixelBufferAdaptor.append returned FALSE @ pts=\(outPTS)")
                    LOG("   writer.status=\(writer.status.rawValue) (\(writer.status))")
                    LOG("   writer.error=\(writer.error?.localizedDescription ?? "nil")")
                    LOG("   videoInput.isReadyForMoreMediaData=\(videoInput.isReadyForMoreMediaData)")
                    setFailed(); finishVideoPump(); return
                }

                if cancel() { finishVideoPump(); return }
            }
        }

        // AUDIO pump
        if let aOut = audioOutput, let aIn = audioInput {
            group.enter()
            aIn.requestMediaDataWhenReady(on: audioQueue) {
                while aIn.isReadyForMoreMediaData {
                    if cancel() { finishAudioPump(aIn); return }

                    guard let sb = aOut.copyNextSampleBuffer() else {
                        finishAudioPump(aIn); return
                    }

                    if cancel() { finishAudioPump(aIn); return }

                    if !aIn.append(sb) {
                        setFailed(); finishAudioPump(aIn); return
                    }

                    if cancel() { finishAudioPump(aIn); return }
                }
            }
        }

        // Wait for pumps
        group.wait()

        if cancel() {
            reader.cancelReading()
            writer.cancelWriting()
            Self.cleanupTemp(tempURL)
            let e = EncodeError(.cancelled, "Encode cancelled.")
            emit(.failed(e))
            return .failure(e)
        }

        if getFailed() || reader.status == .failed || writer.status == .failed {
            reader.cancelReading()
            writer.cancelWriting()
            Self.cleanupTemp(tempURL)
            let msg = writer.error?.localizedDescription
                ?? reader.error?.localizedDescription
                ?? "Unknown encode failure"
            let e = EncodeError(.pipelineFailed, msg)
            emit(.failed(e))
            return .failure(e)
        }

        emit(.phase(.finalizing))

        // Finish writing (synchronous wait via semaphore to return Result)
        let sema = DispatchSemaphore(value: 0)
        var finalResult: Result<EncodeResult, EncodeError> = .failure(.init(.unknown, "Finalization did not run."))

        writer.finishWriting {
            defer { sema.signal() }

            guard writer.status == .completed else {
                Self.cleanupTemp(tempURL) // best-effort remove temp encode

                // NEW: remove empty .mrencode_tmp if applicable
                let tmpDir = tempURL.deletingLastPathComponent()
                if tmpDir.lastPathComponent == ".mrencode_tmp" {
                    Self.cleanupEmptyDir(tmpDir)
                }

                let e = EncodeError(.writerFailed, writer.error?.localizedDescription ?? "Writer did not complete")
                emit(.failed(e))
                finalResult = .failure(e)
                return
            }

            let fm = FileManager.default

            do {
                // Ensure parent directory exists (safe no-op if already exists)
                try fm.createDirectory(
                    at: req.outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                LOG("🧪 checkpoint 2: output directory ensured")
                // Finalize temp → final using unified overwrite + cross-volume logic
                try OutputFinalizer.finalize(
                    tempURL: tempURL,
                    finalURL: req.outputURL,
                    options: .init(allowOverwrite: req.allowOverwrite)
                )
                LOG("🧪 checkpoint 3: reader created")

                // At this point tempURL should be gone, but keep a last-resort sweep.
                Self.cleanupTemp(tempURL)

                // NEW: remove empty .mrencode_tmp if applicable
                let tmpDir = tempURL.deletingLastPathComponent()
                if tmpDir.lastPathComponent == ".mrencode_tmp" {
                    Self.cleanupEmptyDir(tmpDir)
                }
                LOG("🧪 checkpoint 4: videoOutput added to reader")

                let r = EncodeResult(
                    outputURL: req.outputURL,
                    durationSeconds: durationSeconds > 0 ? durationSeconds : nil,
                    framesEncoded: Int(encodedFrames)
                )
                emit(.completed(r))
                finalResult = .success(r)
                LOG("🧪 checkpoint 5: writer created at tempURL = \(tempURL.path)")

            } catch {
                // Best-effort cleanup (do NOT try to chase .sb-* anymore)
                Self.cleanupTemp(tempURL)

                // NEW: remove empty .mrencode_tmp if applicable
                let tmpDir = tempURL.deletingLastPathComponent()
                if tmpDir.lastPathComponent == ".mrencode_tmp" {
                    Self.cleanupEmptyDir(tmpDir)
                }
                LOG("🧪 checkpoint 8: about to call writer.startWriting()")
                let e = EncodeError(.finalizeFailed, "Failed to finalize output: \(error.localizedDescription)")
                emit(.failed(e))
                finalResult = .failure(e)
            }
        }

        sema.wait()
        return finalResult
    }

    private static func cleanupTemp(_ url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        try? fm.removeItem(at: url)
    }

    private static func cleanupEmptyDir(_ dir: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: dir.path),
              items.isEmpty else { return }
        try? fm.removeItem(at: dir)
    }
}
