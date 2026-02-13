//
//  Metal42210Converter.swift
//  MrEncode
//
//  4:2:2 YCbCr 10-bit bi-planar converter
//  Preserves full vertical chroma resolution for better edge quality
//

import Foundation
import Metal
import CoreVideo
import AVFoundation

final class Metal42210Converter {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private var textureCache: CVMetalTextureCache?
    
    init?() {
            fputs(s + "\n", stderr)
        }

        guard let dev = MTLCreateSystemDefaultDevice() else {
            return nil
        }

        guard let queue = dev.makeCommandQueue() else {
            return nil
        }

        guard let library = dev.makeDefaultLibrary() else {
            return nil
        }

        let kernelName = "bgra_to_p210_709_fullrange"
        guard let kernel = library.makeFunction(name: kernelName) else {
            return nil
        }

        let pipeline: MTLComputePipelineState
        do {
            pipeline = try dev.makeComputePipelineState(function: kernel)
        } catch {
            return nil
        }

        self.device = dev
        self.commandQueue = queue
        self.pipelineState = pipeline

        // Pre-create texture cache (reused across frames)
        let rc = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, dev, nil, &textureCache)
        if rc != kCVReturnSuccess {
        } else {
        }
    }

    
    func convert(srcPB: CVPixelBuffer, dstPB: CVPixelBuffer) -> Bool {
        guard let cache = textureCache else { return false }
        
        let w = CVPixelBufferGetWidth(srcPB)
        let h = CVPixelBufferGetHeight(srcPB)
        
        // Create Metal texture from source BGRA pixel buffer
        var srcTexRef: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, srcPB, nil,
            .bgra8Unorm, w, h, 0, &srcTexRef
        ) == kCVReturnSuccess,
              let srcTex = srcTexRef,
              let srcTexture = CVMetalTextureGetTexture(srcTex)
        else { return false }
        
        // Create Metal textures from destination Y and UV planes directly
        var yTexRef: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, dstPB, nil,
            .r16Unorm, w, h, 0, &yTexRef  // Plane 0: Y (16-bit single channel)
        ) == kCVReturnSuccess,
              let yTex = yTexRef,
              let yTexture = CVMetalTextureGetTexture(yTex)
        else { return false }
        
        var uvTexRef: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, dstPB, nil,
            .rg16Unorm, w/2, h, 1, &uvTexRef  // Plane 1: UV (16-bit dual channel, 4:2:2)
        ) == kCVReturnSuccess,
              let uvTex = uvTexRef,
              let uvTexture = CVMetalTextureGetTexture(uvTex)
        else { return false }
        
        // Create command buffer and encoder
        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeComputeCommandEncoder()
        else { return false }
        
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(srcTexture, index: 0)
        encoder.setTexture(yTexture, index: 1)
        encoder.setTexture(uvTexture, index: 2)
        
        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let numGroups = MTLSize(
            width: (w + 15) / 16,
            height: (h + 15) / 16,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(numGroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        
        return true
    }
    
    func makePixelBuffer42210(width: Int, height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange),
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        let r = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                   kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange,
                                   attrs as CFDictionary, &pb)
        return (r == kCVReturnSuccess) ? pb : nil
    }

}



