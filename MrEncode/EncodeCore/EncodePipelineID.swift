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
    case hevc42010
    case hevc42210
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
        case .h264:
            return .h264
        case .hevc:
            return .hevc42010
        case .bypass:
            return .h264
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
                    let bitrate = EncodeCore.estimateBitrate(codecFamily: .h264, qualityIndex: qi, width: w, height: h, fps: fps)
                    let hint = EncodeCore.vtQualityHint(codecFamily: .h264, qualityIndex: qi)
                    return .init(
                        averageBitrateBps: bitrate,
                        vtQualityHint: hint,
                        keyframeIntervalSeconds: 10.0,
                        allowFrameReordering: true
                    )
                }
            )

        case .hevc42010:
            return EncodePipelineDescriptor(
                id: .hevc42010,
                codec: .hevc,
                profileLevelVT: (kVTProfileLevel_HEVC_Main10_AutoLevel as CFString),
                pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                metalKernelName: "bgra_to_p010_709_videorange",
                makeConverter: { Metal42010Converter(kernelName: "bgra_to_p010_709_videorange") },
                expectsVideoRange: true,
                nclcMatrix: nil,
                qualityMap: { qi, w, h, fps in
                    let bitrate = EncodeCore.estimateBitrate(codecFamily: .hevc42010, qualityIndex: qi, width: w, height: h, fps: fps)
                    let hint = EncodeCore.vtQualityHint(codecFamily: .hevc42010, qualityIndex: qi)
                    return .init(
                        averageBitrateBps: bitrate,
                        vtQualityHint: hint,
                        keyframeIntervalSeconds: 10.0,
                        allowFrameReordering: true
                    )
                }
            )

        case .hevc42210:
            return EncodePipelineDescriptor(
                id: .hevc42210,
                codec: .hevc,
                profileLevelVT: (kVTProfileLevel_HEVC_Main42210_AutoLevel as CFString),
                pixelFormat: kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange,
                // NOTE: kernel name is historically "fullrange" but it performs limited-range mapping.
                metalKernelName: "bgra_to_p210_709_fullrange",
                makeConverter: { Metal42210Converter(kernelName: "bgra_to_p210_709_fullrange") },
                expectsVideoRange: true,
                nclcMatrix: nil,
                qualityMap: { qi, w, h, fps in
                    let bitrate = EncodeCore.estimateBitrate(codecFamily: .hevc42210, qualityIndex: qi, width: w, height: h, fps: fps)
                    let hint = EncodeCore.vtQualityHint(codecFamily: .hevc42210, qualityIndex: qi)
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
