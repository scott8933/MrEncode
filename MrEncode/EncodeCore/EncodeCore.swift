//
//  EncodeCore.swift
//  MrEncode
//
//  Created by scott ulrich on 2/2/26.
//


//
//  EncodeCore.swift
//  MrEncode
//
//  Shared encoding logic used by both EncodeGUI (GUI) and EncodeCLI (CLI).
//  Contains everything that must be identical between the two paths:
//    - Bitrate estimation (the tuned quality curve)
//    - Compression property assembly
//    - Video composition (scale/pad/anchor)
//    - Dimension computation & alignment
//    - Frame duration snapping
//    - NCLC helpers (container-level + per-frame pixel buffer)
//    - Audio settings
//    - Per-frame filtering (chroma smoothing, luma sharpen)
//
//  Does NOT contain: progress reporting, cancellation, output URL resolution,
//  AppCore/AppState mutation, or any CLI-specific I/O. Those stay in the callers.
//

import Foundation
import AVFoundation
import VideoToolbox
import CoreImage
import CoreGraphics

enum EncodeCore {

    // MARK: - Dimension alignment

    /// Round width and height up to the nearest multiple of `alignment`.
    static func alignDimensions(_ size: (width: Int, height: Int), alignment: Int = 2) -> (width: Int, height: Int) {
        func up(_ v: Int) -> Int {
            let a = max(2, alignment)
            return ((v + a - 1) / a) * a
        }
        return (up(size.width), up(size.height))
    }

    /// Compute the pre-alignment target size from source track + settings.
    static func computeTargetDimensions(videoTrack: AVAssetTrack, settings: Settings) -> (width: Int, height: Int) {
        let natural = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
        let srcW = Int(abs(natural.width))
        let srcH = Int(abs(natural.height))

        switch settings.scale {
        case .oneToOne:
            return (srcW, srcH)
        case .half, .quarter:
            let f = settings.scale.factor
            return (max(2, Int(Double(srcW) * f)), max(2, Int(Double(srcH) * f)))
        case .custom:
            return (max(2, settings.customScaleWidth), max(2, settings.customScaleHeight))
        }
    }

    // MARK: - Frame rate snapping

    /// Snap a track's frame duration to a canonical timescale so NTSC rates
    /// (23.976, 29.97, 59.94) don't drift into weird decimals.
    static func snappedFrameDuration(for track: AVAssetTrack) -> CMTime {
        let fpsNom = Double(track.nominalFrameRate)

        // NTSC drop-frame rates
        if abs(fpsNom - 23.976) < 0.02 || abs(fpsNom - 23.98) < 0.02 {
            return CMTime(value: 1001, timescale: 24000)
        }
        if abs(fpsNom - 29.97) < 0.02 {
            return CMTime(value: 1001, timescale: 30000)
        }
        if abs(fpsNom - 59.94) < 0.02 {
            return CMTime(value: 1001, timescale: 60000)
        }

        // Common integer rates
        let commonInts: [Int32] = [24, 25, 30, 48, 50, 60]
        for r in commonInts {
            if abs(fpsNom - Double(r)) < 0.01 {
                return CMTime(value: 1, timescale: r)
            }
        }

        // Fall back to minFrameDuration, normalised to timescale 600
        let mfd = track.minFrameDuration
        if mfd.isValid, mfd.value > 0, mfd.timescale > 0 {
            return CMTimeConvertScale(mfd, timescale: 600, method: .roundHalfAwayFromZero)
        }

        return CMTime(value: 1, timescale: 30)
    }

    /// Derive FPS from the snapped frame duration.
    static func snappedFPS(for track: AVAssetTrack) -> Double {
        let fd = snappedFrameDuration(for: track)
        let s  = CMTimeGetSeconds(fd)
        return (s > 0) ? (1.0 / s) : 30.0
    }

    /// Table-driven exact frame duration for a known nominal FPS value
    /// (useful when you don't have the track object handy).
    static func exactFrameDuration(for nominalFPS: Double) -> CMTime {
        let table: [(fps: Double, dur: CMTime)] = [
            (24000.0/1001.0, CMTime(value: 1001, timescale: 24000)),
            (30000.0/1001.0, CMTime(value: 1001, timescale: 30000)),
            (60000.0/1001.0, CMTime(value: 1001, timescale: 60000)),
            (24.0,  CMTime(value: 1, timescale: 24)),
            (25.0,  CMTime(value: 1, timescale: 25)),
            (30.0,  CMTime(value: 1, timescale: 30)),
            (50.0,  CMTime(value: 1, timescale: 50)),
            (60.0,  CMTime(value: 1, timescale: 60))
        ]
        for (fps, dur) in table {
            if abs(nominalFPS - fps) < 0.02 { return dur }
        }
        let fps = max(1.0, nominalFPS)
        return CMTime(seconds: 1.0 / fps, preferredTimescale: 60000)
    }

    // MARK: - Bitrate estimation

    /// The tuned quality-curve shared by GUI and CLI.
    /// Maps settings.qualityCRF (14–30) through gamma shaping, a Gaussian
    /// midrange bump (HEVC only), and a top-end knee into a final bitrate.
    static func estimateBitrate(settings: Settings, width: Int, height: Int, fps: Double) -> Int {
        // 1) Map stored CRF (14..30) to q in 0..1 (higher = better)
        let crfMin = 14.0
        let crfMax = 30.0
        let crf    = min(max(Double(settings.qualityCRF), crfMin), crfMax)
        let t      = (crf - crfMin) / (crfMax - crfMin)   // 0 (best) … 1 (worst)
        let q      = 1.0 - t                               // 1 (best) … 0 (worst)

        // 2) Baseline bpppf envelope per codec
        let bpppfRange: (low: Double, high: Double)
        switch settings.codec {
        case .hevc420, .hevc422:
            // Heavier midrange for perceptual parity vs Compressor.
            bpppfRange = (0.020, 0.090)
        case .h264:
            bpppfRange = (0.060, 0.160)
        case .bypass:
            bpppfRange = (0.060, 0.160)
        }


        // 3) Midrange gamma shaping (lifts 75% without inflating endpoints)
        let shapedQ = pow(q, 0.70)
        var bpppf  = bpppfRange.low + (bpppfRange.high - bpppfRange.low) * shapedQ

        // Gaussian midrange lift (HEVC only) — pushes "75%" perceptual quality
        // upward without excessively inflating endpoints.
        if settings.codec == .hevc420 || settings.codec == .hevc422 {
            let center     = 0.75
            let width      = 0.18
            let x          = (q - center) / width
            let bump       = exp(-(x * x))        // 0…1
            let midBoostMax = 1.35                 // at center: ×(1 + 1.35) ≈ 2.35×
            bpppf *= (1.0 + midBoostMax * bump)
        }

        // 4) Floor protection — 0% is still usable
        let bpppfFloor: Double
        switch settings.codec {
        case .hevc420, .hevc422: bpppfFloor = 0.005
        case .h264:              bpppfFloor = 0.025
        case .bypass:            bpppfFloor = 0.025
        }
        bpppf = max(bpppf, bpppfFloor)

        // 5) Top-end knee — aggressive ramp so 100% can actually max out
        let knee = 0.85
        if q > knee {
            let x     = (q - knee) / (1.0 - knee)   // 0…1 above knee
            let boost = 1.0 + 9.0 * (x * x)         // quadratic ramp, 1× … 10×
            bpppf *= boost
        }

        // 6) Convert to bits/sec
        let pxPerFrame = Double(width * height)
        let bitsPerSec = pxPerFrame * fps * bpppf

        // 7) Clamp with a bpppf-derived max (resolution/fps aware)
        let isHEVC = (settings.codec == .hevc420 || settings.codec == .hevc422)
        let maxBpppf: Double = isHEVC ? 1.0 : 1.5
        let maxBps   = pxPerFrame * fps * maxBpppf

        return Int(min(max(bitsPerSec, 100_000.0), maxBps))
    }
    
    // MARK: - Codec & compression properties

    /// Returns (AVVideoCodecKey value, optional profile-level string).
    ///
    /// NOTE: This is now descriptor-driven. Settings.codec only influences the *default* pipeline choice
    /// (via EncodePipelineDescriptor.defaultID(for:)), but the actual codec/profile come from the pipeline.
    static func vtCodecSettings(settings: Settings) -> (codecKey: String, profileLevel: String?) {
        // Keep this for any legacy call sites. The new path should prefer pipeline.codec/profileLevelVT.
        switch settings.codec {
        case .h264:
            return (AVVideoCodecType.h264.rawValue, nil)

        case .hevc420:
            return (AVVideoCodecType.hevc.rawValue, (kVTProfileLevel_HEVC_Main10_AutoLevel as String))

        case .hevc422:
            return (AVVideoCodecType.hevc.rawValue, (kVTProfileLevel_HEVC_Main42210_AutoLevel as String))

        case .bypass:
            return (AVVideoCodecType.h264.rawValue, nil)
        }
    }
    
    // Settings stores CRF [14...30] for preset compatibility.
    // Convert to user-facing Quality Index [0...100] where higher = better.
    static func qualityIndexFromSettings(_ settings: Settings) -> Double {
        let crfMin = 14
        let crfMax = 30
        let crf = min(max(settings.qualityCRF, crfMin), crfMax)

        let t = Double(crf - crfMin) / Double(crfMax - crfMin) // 0(best)..1(worst)
        let q = 1.0 - t                                        // 1(best)..0(worst)
        return q * 100.0
    }


    /// Build the full video-input settings dictionary (pipeline-driven).
    /// Peak is 6× the raw bitrate (H.264 only). Quality hint is pipeline-mapped.
    /// No pixel-transfer override — let VT pick its own defaults.
    static func videoInputSettings(
        settings: Settings,
        width: Int,
        height: Int,
        fps: Double,
        pipeline: EncodePipelineDescriptor
    ) -> [String: Any] {

        // Quality Index bridge for now (until Settings stores 0..100 directly):
        // CRF 14 (best) .. 30 (worst)  =>  QualityIndex 100 .. 0
        let crfMin = 14.0
        let crfMax = 30.0
        let crf    = min(max(Double(settings.qualityCRF), crfMin), crfMax)
        let t      = (crf - crfMin) / (crfMax - crfMin)
        let qi     = (1.0 - t) * 100.0

        let tuning = pipeline.qualityMap(qi, width, height, fps)

        var compressionProps: [String: Any] = [
            AVVideoAllowFrameReorderingKey: tuning.allowFrameReordering,
            AVVideoMaxKeyFrameIntervalKey:  max(1, Int(round(fps * tuning.keyframeIntervalSeconds)))
        ]

        if let bps = tuning.averageBitrateBps {
            compressionProps[AVVideoAverageBitRateKey] = bps

            // VT-native key improves compliance (especially HEVC)
            compressionProps[kVTCompressionPropertyKey_AverageBitRate as String] = bps

            // DataRateLimits can be unsupported for HEVC encoders (and can crash at AVAssetWriterInput init).
            // Keep it for H.264 only.
            if pipeline.id == .h264 {
                let peakBps = Int(Double(bps) * 6.0)
                compressionProps[kVTCompressionPropertyKey_DataRateLimits as String] = [
                    peakBps, 1
                ] as CFArray
            }
        }


        if let pl = pipeline.profileLevelVT {
            compressionProps[AVVideoProfileLevelKey] = pl
        }

        if let hint = tuning.vtQualityHint {
            compressionProps[kVTCompressionPropertyKey_Quality as String] = hint
        }

        // Prefer HW by default.
        let encoderSpec: [String: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder  as String: true,
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: false
        ]

        return [
            AVVideoCodecKey:                 pipeline.codec.rawValue,
            AVVideoWidthKey:                 width,
            AVVideoHeightKey:                height,
            AVVideoCompressionPropertiesKey: compressionProps,
            AVVideoEncoderSpecificationKey:  encoderSpec
        ]
    }

    /// Wrapper: preserves legacy call sites (engine can call this, or call the overload directly).
    static func videoInputSettings(settings: Settings, width: Int, height: Int, fps: Double) -> [String: Any] {
        let pid = EncodePipelineDescriptor.defaultID(for: settings)
        let pipeline = EncodePipelineDescriptor.make(pid)
        return videoInputSettings(settings: settings, width: width, height: height, fps: fps, pipeline: pipeline)
    }

    // MARK: - Audio settings

    /// Standard AAC output settings used by both paths.
    static let audioOutputSettings: [String: Any] = [
        AVFormatIDKey:            kAudioFormatMPEG4AAC,
        AVNumberOfChannelsKey:    2,
        AVSampleRateKey:          48000,
        AVEncoderBitRateKey:      192000
    ]

    /// Reader-side settings — decode to linear PCM so the writer
    /// can re-encode to AAC.
    static let audioReaderSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM
    ]

    // MARK: - Video composition (scale / pad / anchor)

    /// Build an AVMutableVideoComposition that scales the source track into
    /// `renderSize`, using `contentSize` as the pre-alignment target so that
    /// alignment padding doesn't stretch the image.
    /// Orientation is baked into the layer transform; writer transform should be .identity.
    static func makeVideoComposition(
        track:       AVAssetTrack,
        contentSize: (width: Int, height: Int),
        renderSize:  (width: Int, height: Int),
        settings:    Settings
    ) -> AVMutableVideoComposition {

        let comp = AVMutableVideoComposition()
        comp.renderSize    = CGSize(width: renderSize.width, height: renderSize.height)
        comp.frameDuration = snappedFrameDuration(for: track)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: track.asset?.duration ?? .zero)

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)

        // Source size in display orientation
        let oriented = track.naturalSize.applying(track.preferredTransform)
        let srcW = CGFloat(abs(oriented.width))
        let srcH = CGFloat(abs(oriented.height))
        let dstW = CGFloat(renderSize.width)
        let dstH = CGFloat(renderSize.height)

        let anchor: BurnInPosition = (settings.scale == .custom) ? settings.customScaleAnchor : .center

        if settings.scale == .custom {
            let mode = settings.customScaleMode
            let sx   = dstW / srcW
            let sy   = dstH / srcH

            let scaleX:  CGFloat
            let scaleY:  CGFloat
            let scaledW: CGFloat
            let scaledH: CGFloat

            switch mode {
            case .stretch:
                scaleX  = sx;  scaleY  = sy
                scaledW = dstW; scaledH = dstH
            case .fit:
                let s   = min(sx, sy)
                scaleX  = s;   scaleY  = s
                scaledW = srcW * s; scaledH = srcH * s
            case .fill:
                let s   = max(sx, sy)
                scaleX  = s;   scaleY  = s
                scaledW = srcW * s; scaledH = srcH * s
            }

            let (tx, ty) = anchorTranslation(dstW: dstW, dstH: dstH, scaledW: scaledW, scaledH: scaledH, anchor: anchor)

            // Bake orientation; writer transform stays .identity
            let t = track.preferredTransform
                .concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
                .concatenating(CGAffineTransform(translationX: tx, y: ty))

            layer.setTransform(t, at: .zero)

        } else {
            // Non-custom (1:1, half, quarter): uniform scale to contentSize,
            // then pad/translate into the evenised renderSize.
            let contentW = CGFloat(contentSize.width)
            let contentH = CGFloat(contentSize.height)
            let scale    = min(contentW / srcW, contentH / srcH)
            let scaledW  = srcW * scale
            let scaledH  = srcH * scale

            let (tx, ty) = anchorTranslation(dstW: dstW, dstH: dstH, scaledW: scaledW, scaledH: scaledH, anchor: anchor)

            let t = track.preferredTransform
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: tx, y: ty))

            layer.setTransform(t, at: .zero)
        }

        instruction.layerInstructions = [layer]
        comp.instructions = [instruction]
        return comp
    }

    /// Anchor-based translation for placing scaled content inside the render frame.
    static func anchorTranslation(
        dstW: CGFloat, dstH: CGFloat,
        scaledW: CGFloat, scaledH: CGFloat,
        anchor: BurnInPosition
    ) -> (tx: CGFloat, ty: CGFloat) {
        let remW = dstW - scaledW
        let remH = dstH - scaledH

        switch anchor {
        case .upperLeft:    return (0,          0)
        case .upperCenter:  return (remW * 0.5, 0)
        case .upperRight:   return (remW,       0)
        case .middleLeft:   return (0,          remH * 0.5)
        case .center:       return (remW * 0.5, remH * 0.5)
        case .middleRight:  return (remW,       remH * 0.5)
        case .lowerLeft:    return (0,          remH)
        case .lowerCenter:  return (remW * 0.5, remH)
        case .lowerRight:   return (remW,       remH)
        }
    }

    // MARK: - NCLC helpers

    /// Determine which NCLC triplet to stamp, if any.
    /// "No Change" → nil (true passthrough, no tagging).
    static func nclcTripletToApply(settings: Settings, meta: MediaMetadata) -> NCLCMap.Triplet? {
        let tag = settings.nclcTag.trimmingCharacters(in: .whitespacesAndNewlines)

        if tag.lowercased() == "no change" {
            return nil
        }
        return NCLCMap.lookup(labelOrCode: tag)
    }

    /// Container-level NCLC: the AVVideoColorProperties dictionary that goes
    /// into videoInputSettings alongside the codec key.  Uses the AVFoundation
    /// string constants (distinct from the CoreVideo CV* constants used for
    /// per-frame pixel buffer attachments).
    static func nclcToAVVideoColorProperties(triplet: NCLCMap.Triplet) -> [String: String] {
        func primaries(_ c: String) -> String {
            switch c {
            case "1":  return AVVideoColorPrimaries_ITU_R_709_2
            case "9":  return AVVideoColorPrimaries_ITU_R_2020
            case "12": return AVVideoColorPrimaries_P3_D65
            default:   return AVVideoColorPrimaries_ITU_R_709_2
            }
        }
        func trc(_ c: String) -> String {
            switch c {
            case "1":  return AVVideoTransferFunction_ITU_R_709_2
            case "13":
                // AVFoundation doesn't reliably expose sRGB TRC on macOS;
                // tag as 709 at container level, rely on pixel buffer attachments
                // for true sRGB when explicitly requested.
                return AVVideoTransferFunction_ITU_R_709_2
            case "16": return AVVideoTransferFunction_SMPTE_ST_2084_PQ
            case "18": return AVVideoTransferFunction_ITU_R_2100_HLG
            default:   return AVVideoTransferFunction_ITU_R_709_2
            }
        }
        func matrix(_ c: String) -> String {
            switch c {
            case "1":       return AVVideoYCbCrMatrix_ITU_R_709_2
            case "5", "6":  return AVVideoYCbCrMatrix_ITU_R_601_4
            case "9", "10": return AVVideoYCbCrMatrix_ITU_R_2020
            default:        return AVVideoYCbCrMatrix_ITU_R_709_2
            }
        }

        return [
            AVVideoColorPrimariesKey:    primaries(triplet.primaries),
            AVVideoTransferFunctionKey:  trc(triplet.trc),
            AVVideoYCbCrMatrixKey:       matrix(triplet.matrix)
        ]
    }

    /// Per-frame pixel buffer attachments — CoreVideo CV* constants.
    /// Applied every frame via CVBufferSetAttachment.
    static func nclcToColorAttachments(triplet: NCLCMap.Triplet) -> [String: Any] {
        var a: [String: Any] = [:]

        let primaries: CFString = {
            switch triplet.primaries {
            case "1":  return kCVImageBufferColorPrimaries_ITU_R_709_2
            case "5":  return kCVImageBufferColorPrimaries_EBU_3213
            case "6":  return kCVImageBufferColorPrimaries_SMPTE_C
            case "9":  return kCVImageBufferColorPrimaries_ITU_R_2020
            case "12": return kCVImageBufferColorPrimaries_P3_D65
            default:   return kCVImageBufferColorPrimaries_ITU_R_709_2
            }
        }()
        a[kCVImageBufferColorPrimariesKey as String] = primaries

        let trc: CFString = {
            switch triplet.trc {
            case "1":  return kCVImageBufferTransferFunction_ITU_R_709_2
            case "4":  return kCVImageBufferTransferFunction_UseGamma
            case "5":  return kCVImageBufferTransferFunction_UseGamma
            case "13": return kCVImageBufferTransferFunction_sRGB
            case "16": return kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
            case "18": return kCVImageBufferTransferFunction_ITU_R_2100_HLG
            default:   return kCVImageBufferTransferFunction_ITU_R_709_2
            }
        }()
        a[kCVImageBufferTransferFunctionKey as String] = trc

        if triplet.trc == "4" { a[kCVImageBufferGammaLevelKey as String] = 2.2 }
        if triplet.trc == "5" { a[kCVImageBufferGammaLevelKey as String] = 2.8 }

        let matrix: CFString = {
            switch triplet.matrix {
            case "1":  return kCVImageBufferYCbCrMatrix_ITU_R_709_2
            case "5":  return kCVImageBufferYCbCrMatrix_ITU_R_601_4
            case "6":  return kCVImageBufferYCbCrMatrix_ITU_R_601_4
            case "9":  return kCVImageBufferYCbCrMatrix_ITU_R_2020
            case "10": return kCVImageBufferYCbCrMatrix_ITU_R_2020
            default:   return kCVImageBufferYCbCrMatrix_ITU_R_709_2
            }
        }()
        a[kCVImageBufferYCbCrMatrixKey as String] = matrix

        return a
    }

    /// Stamp NCLC onto a pixel buffer (per-frame, during encoding).
    static func applyNCLCToPixelBuffer(_ pixelBuffer: CVPixelBuffer, triplet: NCLCMap.Triplet) {
        for (key, value) in nclcToColorAttachments(triplet: triplet) {
            CVBufferSetAttachment(pixelBuffer, key as CFString, value as CFTypeRef, .shouldPropagate)
        }
    }

    /// Stamp NCLC onto an AVAssetWriter (file-level metadata).
    static func applyNCLCToWriter(_ writer: AVAssetWriter, triplet: NCLCMap.Triplet) {
        var items: [AVMetadataItem] = []
        for (key, value) in nclcToColorAttachments(triplet: triplet) {
            let item = AVMutableMetadataItem()
            item.keySpace = .quickTimeMetadata
            item.key      = key as NSString
            if let s = value as? String        { item.value = s as NSString }
            else if let n = value as? NSNumber { item.value = n }
            items.append(item)
        }
        writer.metadata = items
    }

    // MARK: - Per-frame filtering

    /// Chroma-only Gaussian smoothing.  Decomposes into luma + chroma residual,
    /// blurs only the chroma, recombines.  Helps 4444→420 chroma breakup.
    /// Called when qualityCRF ≤ 22 (i.e. higher quality settings where the
    /// chroma artefacts are most visible).
    static func applyChromaSmoothing(to pixelBuffer: CVPixelBuffer, radius: Double = 0.7) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Approximate luma extraction (Rec.709 coefficients)
        let luma = ciImage.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector":     CIVector(x: 0.2126, y: 0, z: 0, w: 0),
            "inputGVector":     CIVector(x: 0, y: 0.7152, z: 0, w: 0),
            "inputBVector":     CIVector(x: 0, y: 0, z: 0.0722, w: 0),
            "inputBiasVector":  CIVector(x: 0, y: 0, z: 0, w: 0)
        ])

        // Color residual ≈ chroma
        let chroma = ciImage.applyingFilter("CIDifferenceBlendMode", parameters: [
            kCIInputBackgroundImageKey: luma
        ])

        // Blur chroma only
        let blurredChroma = chroma.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: radius
        ])

        // Recombine luma + smoothed chroma
        let recombined = blurredChroma.applyingFilter("CIAdditionBlendMode", parameters: [
            kCIInputBackgroundImageKey: luma
        ])

        let context = CIContext(options: [.useSoftwareRenderer: false])
        context.render(recombined, to: pixelBuffer, bounds: ciImage.extent,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    /// Luma-only unsharp-mask sharpen.  Available for use after chroma smoothing
    /// to recover edge crispness lost by the blur pass.  Currently unused in
    /// the pump loop but kept here so both paths can enable it identically.
    static func applyLumaSharpen(to pixelBuffer: CVPixelBuffer, radius: Double = 0.8, amount: Double = 0.25) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let sharpened = ciImage.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey:     radius,
            kCIInputIntensityKey:  amount
        ])

        let context = CIContext()
        context.render(sharpened, to: pixelBuffer, bounds: ciImage.extent,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
    }
}
