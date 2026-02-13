//
//  Metal42010Converter.swift
//  MrEncode
//
//  Created by scott ulrich on 2/11/26.
//


import Foundation
import Metal
import CoreVideo
import CoreMedia

final class Metal42010Converter {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private var cache: CVMetalTextureCache?

    init?() {
        guard let d = MTLCreateSystemDefaultDevice(),
              let q = d.makeCommandQueue()
        else { return nil }

        self.device = d
        self.queue = q

        // Load default library (add .metal file to target)
        guard let lib = d.makeDefaultLibrary(),
              let fn = lib.makeFunction(name: "bgra_to_p010_709_videorange"),
              let ps = try? d.makeComputePipelineState(function: fn)
        else { return nil }

        self.pipeline = ps

        var c: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, d, nil, &c)
        self.cache = c
    }

    /// Convert BGRA srcPB into dstPB (kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange).
    /// dstPB must be allocated from adaptor.pixelBufferPool (correct plane layout).
    func convert(srcPB: CVPixelBuffer, dstPB: CVPixelBuffer) -> Bool {
        guard let cache else { return false }
        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder()
        else { return false }

        let w = CVPixelBufferGetWidth(srcPB)
        let h = CVPixelBufferGetHeight(srcPB)

        // Wrap src as BGRA8 texture
        var srcTexRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            srcPB,
            nil,
            .bgra8Unorm,
            w,
            h,
            0,
            &srcTexRef
        )
        guard let srcTexRef,
              let srcTex = CVMetalTextureGetTexture(srcTexRef)
        else { return false }

        // Wrap dst planes as textures:
        // plane 0: Y  (16-bit)
        // plane 1: UV (16-bit x2)
        let yW = CVPixelBufferGetWidthOfPlane(dstPB, 0)
        let yH = CVPixelBufferGetHeightOfPlane(dstPB, 0)
        let uvW = CVPixelBufferGetWidthOfPlane(dstPB, 1)
        let uvH = CVPixelBufferGetHeightOfPlane(dstPB, 1)

        var yTexRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            dstPB,
            nil,
            .r16Unorm,
            yW,
            yH,
            0,
            &yTexRef
        )
        guard let yTexRef,
              let yTex = CVMetalTextureGetTexture(yTexRef)
        else { return false }

        var uvTexRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            dstPB,
            nil,
            .rg16Unorm,
            uvW,
            uvH,
            1,
            &uvTexRef
        )
        guard let uvTexRef,
              let uvTex = CVMetalTextureGetTexture(uvTexRef)
        else { return false }

        enc.setComputePipelineState(pipeline)
        enc.setTexture(srcTex, index: 0)
        enc.setTexture(yTex, index: 1)
        enc.setTexture(uvTex, index: 2)

        // Dispatch: one thread per luma pixel (Y), UV written by even-even threads
        let tgW = 16
        let tgH = 16
        let threadsPerGroup = MTLSize(width: tgW, height: tgH, depth: 1)
        let threadsPerGrid = MTLSize(width: w, height: h, depth: 1)

        enc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        enc.endEncoding()

        cmd.commit()
        cmd.waitUntilCompleted()
        return cmd.status == .completed
    }
}
