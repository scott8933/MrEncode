//
//  EncodePipelineID.swift
//  MrEncode
//
//  Created by scott ulrich on 2/13/26.
//


//
//  EncodePipeline.swift
//  MrEncode
//
//  Central descriptor for all encode pipelines (H.264 / HEVC 4:2:0 10-bit / HEVC 4:2:2 10-bit)
//  so EncodeEngine can remain generic plumbing.
//

import Foundation
import AVFoundation
import VideoToolbox
import CoreVideo

/// User-facing selection of an encode pipeline.
public enum EncodePipelineID: String, Codable, Sendable {
    case h264
    case hevc420
    case hevc422
}

/// Minimal protocol so EncodeEngine can plug in a converter without knowing details.
protocol PixelConverter {
    func convert(srcPB: CVPixelBuffer, dstPB: CVPixelBuffer) -> Bool
}

/// Compression “tuning knobs” that vary per pipeline.
/// These are derived from the single user-facing 0..100 Quality Index.
struct PipelineQualityTuning: Sendable {
    /// Average bitrate in bps. If nil, caller may omit AVVideoAverageBitRateKey.
    var averageBitrateBps: Int?
    /// VT quality hint 0..1. If nil, omit kVTCompressionPropertyKey_Quality.
    var vtQualityHint: Double?
    /// Max keyframe interval in seconds.
    var keyframeIntervalSeconds: Double
    /// Allow frame reordering (B-frames) if encoder supports it.
    var allowFrameReordering: Bool
}

/// Pipeline descriptor: everything EncodeEngine needs to configure writer + adaptor + converter.
struct EncodePipelineDescriptor: Sendable {
    
    init(
        id: EncodePipelineID,
        codec: AVVideoCodecType,
        profileLevelVT: CFString?,
        pixelFormat: OSType,
        metalKernelName: String?,
        makeConverter: @escaping (@Sendable () -> PixelConverter?),
        expectsVideoRange: Bool,
        nclcMatrix: Int?,
        qualityMap: @escaping (@Sendable (_ qualityIndex0to100: Double, _ width: Int, _ height: Int, _ fps: Double) -> PipelineQualityTuning)
    ) {
        self.id = id
        self.codec = codec
        self.profileLevelVT = profileLevelVT
        self.pixelFormat = pixelFormat
        self.metalKernelName = metalKernelName
        self.makeConverter = makeConverter
        self.expectsVideoRange = expectsVideoRange
        self.nclcMatrix = nclcMatrix
        self.qualityMap = qualityMap
    }

    let id: EncodePipelineID

    // Writer / VT
    let codec: AVVideoCodecType
    /// If provided, applied to compression properties.
    let profileLevelVT: CFString?

    // Adaptor pool pixel format
    let pixelFormat: OSType

    // Metal conversion (optional)
    let metalKernelName: String?
    let makeConverter: (@Sendable () -> PixelConverter?)

    // Color / range contract (mostly informational; enforcement happens in kernels + NCLC)
    let expectsVideoRange: Bool
    let nclcMatrix: Int?

    // Quality mapping hook
    let qualityMap: (@Sendable (_ qualityIndex0to100: Double, _ width: Int, _ height: Int, _ fps: Double) -> PipelineQualityTuning)

    func adaptorAttributes(width: Int, height: Int) -> [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
    }

    /// Default selection used when callers do not explicitly override.
    /// This avoids referencing new Settings fields that might not exist yet.
    static func defaultID(for settings: Settings) -> EncodePipelineID {
        switch settings.codec {
        case .hevc420: return .hevc420
        case .hevc422: return .hevc422
        case .h264:    return .h264
        case .bypass:  return .h264 // or unused
        }
    }

    static func make(_ id: EncodePipelineID) -> EncodePipelineDescriptor {
        switch id {
        case .h264:
            return EncodePipelineDescriptor(
                id: .h264,
                codec: .h264,
                profileLevelVT: nil,
                pixelFormat: kCVPixelFormatType_32BGRA,
                metalKernelName: nil,
                makeConverter: { nil },
                expectsVideoRange: true,
                nclcMatrix: nil,
                qualityMap: { qi, w, h, fps in
                    let bitrate = EncodeCore.estimateBitrate(codecFamily: EncodeCore.CodecFamily.h264, qualityIndex: qi, width: w, height: h, fps: fps)
                    let hint = EncodeCore.vtQualityHint(codecFamily: EncodeCore.CodecFamily.h264, qualityIndex: qi)
                    return .init(
                        averageBitrateBps: bitrate,
                        vtQualityHint: hint,
                        keyframeIntervalSeconds: 10.0,
                        allowFrameReordering: true
                    )
                }
            )

        case .hevc420:
            return EncodePipelineDescriptor(
                id: .hevc420,
                codec: .hevc,
                profileLevelVT: (kVTProfileLevel_HEVC_Main10_AutoLevel as CFString),
                pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                metalKernelName: "bgra_to_p010_709_videorange",
                makeConverter: { Metal42010Converter(kernelName: "bgra_to_p010_709_videorange") },
                expectsVideoRange: true,
                nclcMatrix: nil,
                qualityMap: { qi, w, h, fps in
                    let bitrate = EncodeCore.estimateBitrate(codecFamily: EncodeCore.CodecFamily.hevc420, qualityIndex: qi, width: w, height: h, fps: fps)
                    let hint = EncodeCore.vtQualityHint(codecFamily: EncodeCore.CodecFamily.hevc420, qualityIndex: qi)
                    return .init(
                        averageBitrateBps: bitrate,
                        vtQualityHint: hint,
                        keyframeIntervalSeconds: 10.0,
                        allowFrameReordering: true
                    )
                }
            )

        case .hevc422:
            return EncodePipelineDescriptor(
                id: .hevc422,
                codec: .hevc,
                profileLevelVT: (kVTProfileLevel_HEVC_Main42210_AutoLevel as CFString),
                pixelFormat: kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange,
                metalKernelName: "bgra_to_p210_709_videorange",
                makeConverter: { Metal42210Converter(kernelName: "bgra_to_p210_709_videorange") },
                expectsVideoRange: true,
                nclcMatrix: nil,
                qualityMap: { qi, w, h, fps in
                    let bitrate = EncodeCore.estimateBitrate(codecFamily: EncodeCore.CodecFamily.hevc422, qualityIndex: qi, width: w, height: h, fps: fps)
                    let hint: Double? = nil // HEVC422: drive via bitrate only (avoid VT Quality -> runaway bitrate)
                    return .init(
                        averageBitrateBps: bitrate,
                        vtQualityHint: hint,
                        keyframeIntervalSeconds: 10.0,
                        allowFrameReordering: true
                    )
                }
            )
        }
    }
}


// MARK: - EncodeCore helpers needed by pipeline descriptor (kept here to avoid target/fragment issues)

extension EncodeCore {

    enum CodecFamily: Sendable {
        case h264
        case hevc420
        case hevc422
    }

    /// Map a 0..100 Quality Index into a synthetic CRF (14..30) so we can reuse the tuned curve.
    /// 100 = best (CRF 14), 0 = worst (CRF 30).
    static func qualityIndexToCRF(_ qualityIndex: Double) -> Double {
        let qi = min(max(qualityIndex, 0.0), 100.0)
        let crfMin = 14.0
        let crfMax = 30.0
        return crfMax - (qi / 100.0) * (crfMax - crfMin)
    }

    static func estimateBitrate(codecFamily: CodecFamily, qualityIndex: Double, width: Int, height: Int, fps: Double) -> Int {
        // QualityIndex -> q (0..1), via synthetic CRF
        let crfMin = 14.0
        let crfMax = 30.0
        let crf    = min(max(qualityIndexToCRF(qualityIndex), crfMin), crfMax)
        let t      = (crf - crfMin) / (crfMax - crfMin)   // 0 best .. 1 worst
        let q      = 1.0 - t                               // 1 best .. 0 worst

        // Special-case: HEVC 4:2:2 tuning target (11s @ 30fps, 1180×2556 baseline)
        // Desired: ~38MB @50, ~60MB @75, ~120MB @100 (roughly 28, 42, 84 Mbps).
        // Simple, monotonic model:
        // - Linear bpppf envelope
        // - Gentle headroom above 75 to lift only the top end
        if codecFamily == .hevc422 {
            // Base envelope
            let low: Double  = 0.070   // q=0
            let high: Double = 0.650   // q=1 (before headroom)

            var bpppf = low + (high - low) * q

            // UI-based headroom ONLY in the top band (QI 75→100):
            // - QI=75: 1.0×
            // - QI=100: 2.0×
            do {
                let qiUI = min(max(qualityIndex, 0.0), 100.0)
                if qiUI > 75.0 {
                    let x = (qiUI - 75.0) / 25.0          // 0..1
                    let t = x * x                          // gentle ramp
                    let headroomMax: Double = 1.00         // +100% at 100
                    bpppf *= (1.0 + headroomMax * t)
                }
            }


            // Floor protection
            bpppf = max(bpppf, 0.005)

            // Convert bpppf -> bps
            let w = Double(max(2, width))
            let h = Double(max(2, height))
            let f = max(1.0, fps)
            let bitsPerSec = bpppf * w * h * f

            // Clamp
            let maxBps = 400_000_000.0
            return Int(min(max(bitsPerSec, 100_000.0), maxBps))
        }

        // Baseline bpppf envelope per pipeline (HEVC420 + H.264)
        let bpppfRange: (low: Double, high: Double)
        switch codecFamily {
        case .hevc420:
            bpppfRange = (0.020, 0.090)
        case .h264:
            bpppfRange = (0.060, 0.160)
        case .hevc422:
            // handled above
            bpppfRange = (0.028, 0.115)
        }

        // Midrange shaping
        let shapedQ = pow(q, 0.70)
        var bpppf   = bpppfRange.low + (bpppfRange.high - bpppfRange.low) * shapedQ

        // Gaussian midrange lift (HEVC420 only) — keep legacy behavior
        if codecFamily == .hevc420 {
            let center      = 0.75
            let sigma       = 0.18
            let x           = (q - center) / sigma
            let bump        = exp(-(x * x))
            let midBoostMax = 1.35
            bpppf *= (1.0 + midBoostMax * bump)
        }

        // Floor protection
        let floor: Double = (codecFamily == .h264) ? 0.025 : 0.005
        bpppf = max(bpppf, floor)

        // Convert bpppf -> bps
        let w = Double(max(2, width))
        let h = Double(max(2, height))
        let f = max(1.0, fps)
        let bitsPerSec = bpppf * w * h * f

        // Clamp
        let maxBps = 400_000_000.0
        return Int(min(max(bitsPerSec, 100_000.0), maxBps))
    }


    /// VT "Quality" hint (0..1) derived from Quality Index.
    static func vtQualityHint(codecFamily: CodecFamily, qualityIndex: Double) -> Double {
        let qi = min(max(qualityIndex, 0.0), 100.0)
        let qRaw  = qi / 100.0

        func smoothstep01(_ x: Double) -> Double {
            let t = min(1.0, max(0.0, x))
            return t * t * (3.0 - 2.0 * t)
        }

        // Match HEVC420 remap used by bitrate so VT's internal rate-control isn't "fighting" the UI scale.
        let q: Double
        if codecFamily == .hevc420 {
            if qRaw <= 0.75 {
                let t = smoothstep01(qRaw / 0.75)
                q = 0.25 + (0.50 - 0.25) * t
            } else {
                let t = smoothstep01((qRaw - 0.75) / 0.25)
                q = 0.50 + (0.75 - 0.50) * t
            }
        } else {
            q = qRaw
        }

        // Two-stage curve:
        // 0–50: climb from a conservative floor up to a strong "good" hint.
        // 50–100: accelerate towards near-max hint without going to 1.0 (stability).
        if q <= 0.50 {
            let t = smoothstep01(q / 0.50)
            return 0.28 + (0.88 - 0.28) * t
        } else {
            let t = smoothstep01((q - 0.50) / 0.50)
            let tt = t * t
            return 0.88 + (0.995 - 0.88) * tt
        }
    }
}
