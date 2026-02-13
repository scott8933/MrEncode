//
//  MediaProbeService.swift
//  MrEncode
//
//  Created by scott ulrich on 1/15/26.
//



import Foundation
import AVFoundation

struct MediaBasics: Codable, Equatable {
    let srcW: Int
    let srcH: Int
    let outW: Int
    let outH: Int
    let fps: Double
    let duration: Double
    let hasAudio: Bool
    let isHDR: Bool
}

extension MediaProbeService {

    struct VideoDecodeProbe {
        let hasVideo: Bool
        let canDecode: Bool
    }

    /// Synchronous, fast probe used for import gating.
    /// - Accept if: has at least one video track AND AVAssetReader can start.
    /// - Reject audio-only and undecodable assets.
    static func probeVideoDecode(_ url: URL) -> VideoDecodeProbe {
        let asset = AVURLAsset(url: url)

        let videoTracks = asset.tracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            return VideoDecodeProbe(hasVideo: false, canDecode: false)
        }

        do {
            let reader = try AVAssetReader(asset: asset)

            let outputSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]

            let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false
            reader.add(output)

            return VideoDecodeProbe(
                hasVideo: true,
                canDecode: reader.startReading()
            )

        } catch {
            return VideoDecodeProbe(hasVideo: true, canDecode: false)
        }
    }
}

/// Single owner of probe cache + in-flight tasks.
actor MediaProbeService {

    static let shared = MediaProbeService()

    private var cache: [URL: MediaBasics] = [:]
    private var inFlight: [URL: Task<MediaBasics?, Never>] = [:]

    // MARK: - Probe concurrency limiting (prevents stampedes)

    /// Max concurrent AVFoundation probes running at once.
    /// Keep this small; 2 is a safe default and avoids memory/I/O thrash.
    private let maxConcurrentProbes: Int = 2

    private var probePermits: Int = 2
    private var probeWaiters: [CheckedContinuation<Void, Never>] = []

    private func acquireProbeSlot() async {
        if probePermits > 0 {
            probePermits -= 1
            return
        }
        await withCheckedContinuation { cont in
            probeWaiters.append(cont)
        }
    }

    private func releaseProbeSlot() {
        if !probeWaiters.isEmpty {
            let cont = probeWaiters.removeFirst()
            cont.resume()
        } else {
            probePermits += 1
        }
    }

    // MARK: Public API

    func cachedBasics(for url: URL) -> MediaBasics? {
        cache[url]
    }

    /// Returns cached immediately if available; otherwise starts/joins a background probe Task.
    func probeBasics(url: URL, meta: MediaMetadata, scale: ScaleOption) -> Task<MediaBasics?, Never> {
        if let cached = cache[url] {
            return Task { cached }
        }

        if let existing = inFlight[url] {
            return existing
        }

        let t: Task<MediaBasics?, Never> = Task(priority: .userInitiated) { [weak self] () -> MediaBasics? in
            guard let self else { return nil }

            // Acquire concurrency slot
            await self.acquireProbeSlot()
            
            // Perform async AVFoundation probe
            let result = await MediaProbeService.computeBasics(url: url, meta: meta, scale: scale)
            
            // Release slot
            await self.releaseProbeSlot()

            // Store results back in actor (if not cancelled)
            await self.finish(url: url, result: result)
            return result
        }

        inFlight[url] = t
        return t
    }

    func cancelProbe(for url: URL) {
        inFlight[url]?.cancel()
        inFlight[url] = nil
    }

    func cancelAllProbes(except keep: Set<URL> = []) {
        for (url, task) in inFlight where !keep.contains(url) {
            task.cancel()
        }
        inFlight = inFlight.filter { keep.contains($0.key) }
    }

    func clearCache() {
        cache.removeAll()
    }

    // MARK: Private

    private func finish(url: URL, result: MediaBasics?) {
        // If a task was cancelled, don't commit partial results.
        if Task.isCancelled {
            inFlight[url] = nil
            return
        }
        if let result {
            cache[url] = result
        }
        inFlight[url] = nil
    }

    /// Pure async function using modern AVFoundation async APIs.
    /// Safe to run concurrently without blocking on slow network mounts.
    private static func computeBasics(url: URL, meta: MediaMetadata, scale: ScaleOption) async -> MediaBasics? {
        // Check for cancellation early
        guard !Task.isCancelled else { return nil }
        
        let asset = AVURLAsset(url: url)

        // Load video track asynchronously (won't block on slow mounts)
        guard let tracks = try? await asset.load(.tracks),
              let v = tracks.first(where: { $0.mediaType == .video }) else {
            return nil
        }

        guard !Task.isCancelled else { return nil }

        // Load track properties asynchronously
        guard let naturalSize = try? await v.load(.naturalSize),
              let preferredTransform = try? await v.load(.preferredTransform) else {
            return nil
        }

        let sz = naturalSize.applying(preferredTransform)
        let srcW = Int(abs(sz.width).rounded())
        let srcH = Int(abs(sz.height).rounded())
        guard srcW > 0, srcH > 0 else { return nil }

        let s = scale.factor
        let outW = max(1, Int(round(Double(srcW) * s)))
        let outH = max(1, Int(round(Double(srcH) * s)))

        guard !Task.isCancelled else { return nil }

        // FPS from metadata or track
        var fps = meta.nominalFPS ?? 30.0
        if fps <= 0 {
            if let nominalFrameRate = try? await v.load(.nominalFrameRate), nominalFrameRate > 0 {
                fps = Double(nominalFrameRate)
            }
        }

        // Duration
        let assetDuration: Double
        if let dur = try? await asset.load(.duration), dur.isValid {
            assetDuration = CMTimeGetSeconds(dur)
        } else {
            assetDuration = 0
        }
        
        let durSource = meta.durationSeconds
        let dur = (durSource > 0 ? durSource : assetDuration)
        guard dur.isFinite, dur > 0 else { return nil }

        guard !Task.isCancelled else { return nil }

        // Audio check
        let hasAudio: Bool
        if let audioTracks = try? await asset.loadTracks(withMediaType: .audio) {
            hasAudio = !audioTracks.isEmpty
        } else {
            hasAudio = false
        }

        // HDR check from metadata
        let tf = (meta.transferFunction ?? "").lowercased()
        let isHDR = tf.contains("2084") || tf.contains("pq") || tf.contains("hlg") || tf.contains("2100")

        return MediaBasics(
            srcW: srcW,
            srcH: srcH,
            outW: outW,
            outH: outH,
            fps: fps,
            duration: dur,
            hasAudio: hasAudio,
            isHDR: isHDR
        )
    }
}
