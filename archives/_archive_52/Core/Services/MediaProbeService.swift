//
//  MediaProbeService.swift
//  MrHEVC
//
//  Created by scott ulrich on 1/15/26.
//


//
//  MediaProbeService.swift
//  MrHEVC
//
//  Created by scott ulrich on 1/15/26.
//

import Foundation
import AVFoundation

struct MediaBasics: Sendable {
    let outW: Int
    let outH: Int
    let fps: Double
    let duration: Double
    let hasAudio: Bool
    let isHDR: Bool
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

    /// Run a synchronous body while holding a probe slot.
    private func withProbeSlot<T>(_ body: () -> T) async -> T {
        await acquireProbeSlot()
        defer { releaseProbeSlot() }
        return body()
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

            // Concurrency-limited AVFoundation probe (off-main)
            let result: MediaBasics? = await self.withProbeSlot {
                MediaProbeService.computeBasics(url: url, meta: meta, scale: scale)
            }

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
        // If a task was cancelled, don’t commit partial results.
        if Task.isCancelled {
            inFlight[url] = nil
            return
        }
        if let result {
            cache[url] = result
        }
        inFlight[url] = nil
    }

    /// Pure function (no shared state) – safe to run concurrently.
    private static func computeBasics(url: URL, meta: MediaMetadata, scale: ScaleOption) -> MediaBasics? {
        let asset = AVAsset(url: url)

        guard let v = asset.tracks(withMediaType: .video).first else { return nil }

        let sz = v.naturalSize.applying(v.preferredTransform)
        let srcW = Int(abs(sz.width).rounded())
        let srcH = Int(abs(sz.height).rounded())
        guard srcW > 0, srcH > 0 else { return nil }

        let s = scale.factor
        let outW = max(1, Int(round(Double(srcW) * s)))
        let outH = max(1, Int(round(Double(srcH) * s)))

        let fps = meta.nominalFPS ?? (v.nominalFrameRate > 0 ? Double(v.nominalFrameRate) : 30.0)
        let assetDuration = CMTimeGetSeconds(asset.duration)
        let durSource = meta.durationSeconds
        let dur = (durSource > 0 ? durSource : assetDuration)
        guard dur.isFinite, dur > 0 else { return nil }

        let hasAudio = !asset.tracks(withMediaType: .audio).isEmpty

        let tf = (meta.transferFunction ?? "").lowercased()
        let isHDR = tf.contains("2084") || tf.contains("pq") || tf.contains("hlg") || tf.contains("2100")

        return MediaBasics(outW: outW, outH: outH, fps: fps, duration: dur, hasAudio: hasAudio, isHDR: isHDR)
    }
}
