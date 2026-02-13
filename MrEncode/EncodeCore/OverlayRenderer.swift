//
//  OverlayRenderer.swift
//  MrEncode
//
//  Created by scott ulrich on 1/30/26.
//  Renders text overlays (timecode, frame numbers, filename) onto pixel buffers


import Foundation
import CoreGraphics
import CoreText
import CoreVideo
import AVFoundation

#if !MR_ENCODE_CLI
import AppKit
#endif


/// Handles rendering text overlays onto pixel buffers
enum OverlayRenderer {
    
    // MARK: - Configuration
    
    struct Config {
        let outputSize: CGSize
        let fps: Double
        let startTimecode: String?
        let filename: String
        let settings: Settings
        
        // Derived values
        let fontSize: CGFloat
        let margin: CGFloat
        let lineGap: CGFloat
        let boxPadding: CGFloat
        let textColor: CGColor
        let boxColor: CGColor
        let font: CTFont
        
        init(outputSize: CGSize, fps: Double, startTimecode: String?, filename: String, settings: Settings) {
            self.outputSize = outputSize
            self.fps = fps
            self.startTimecode = startTimecode
            self.filename = filename
            self.settings = settings
            
            // Calculate responsive sizing
            let shortSide = min(outputSize.width, outputSize.height)
            self.fontSize = max(18, min(64, shortSide * 0.035))
            
            // Margin ~1.2% of height (min 8, max 48)
            self.margin = max(8, min(48, outputSize.height * 0.012))
            
            // Gap ~25% of font size (min 2, max 24)
            self.lineGap = max(2, min(24, fontSize * 0.25))
            
            // Box padding ~ fontSize/6 (min 2, max 16)
            self.boxPadding = max(2, min(16, fontSize / 6.0))
            
            // Colors
            self.textColor = OverlayRenderer.colorFromHex(settings.overlayTextColorHex, alpha: settings.overlayTextColorAlpha)
            self.boxColor = OverlayRenderer.colorFromHex(settings.overlayBoxColorHex, alpha: settings.overlayBoxColorAlpha)
            
            // Font (Menlo or system monospaced)
            let fontName = "Menlo-Regular"
            let ctFont = CTFontCreateWithName(fontName as CFString, fontSize, nil)
            self.font = ctFont
        }
    }
    
    // MARK: - Public API
    
    /// Draw overlays onto a pixel buffer for the given frame
    static func drawOverlays(
        on pixelBuffer: CVPixelBuffer,
        frameNumber: Int64,
        config: Config
    ) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        guard let context = createContext(for: pixelBuffer) else { return }
        
        // Prepare overlay requests grouped by position
        let requests = buildOverlayRequests(frameNumber: frameNumber, config: config)
        let grouped = Dictionary(grouping: requests, by: { $0.position })
        
        // Draw each group (stacked if multiple in same position)
        for (position, group) in grouped {
            drawStack(group, at: position, in: context, config: config)
        }
    }
    
    // MARK: - Overlay Requests
    
    private struct OverlayRequest {
        let position: BurnInPosition
        let text: String
    }
    
    private static func buildOverlayRequests(frameNumber: Int64, config: Config) -> [OverlayRequest] {
        var requests: [OverlayRequest] = []
        
        // Timecode
        if config.settings.burnInTimecode {
            let tc = timecodeString(forFrame: frameNumber, config: config)
            requests.append(OverlayRequest(
                position: config.settings.burnInTimecodePosition,
                text: tc
            ))
        }
        
        // Frame number
        if config.settings.burnInFrames {
            let startFrame = startFrameOffset(config: config)
            let displayFrame = Int(frameNumber) + startFrame
            let width = frameNumberWidth(config: config)
            let frameText = String(format: "%0\(width)d", displayFrame)
            requests.append(OverlayRequest(
                position: config.settings.burnInFramesPosition,
                text: frameText
            ))
        }
        
        // Filename
        if config.settings.burnInFilename {
            requests.append(OverlayRequest(
                position: config.settings.burnInFilenamePosition,
                text: config.filename
            ))
        }
        
        return requests
    }
    
    // MARK: - Drawing
    
    private static func drawStack(
        _ requests: [OverlayRequest],
        at position: BurnInPosition,
        in context: CGContext,
        config: Config
    ) {
        for (index, request) in requests.enumerated() {
            drawText(
                request.text,
                at: position,
                stackIndex: index,
                stackCount: requests.count,
                in: context,
                config: config
            )
        }
    }
    
    private static func drawText(
        _ text: String,
        at position: BurnInPosition,
        stackIndex: Int,
        stackCount: Int,
        in context: CGContext,
        config: Config
    ) {
        // Measure text
        let attrString = NSAttributedString(
            string: text,
            attributes: [
                kCTFontAttributeName as NSAttributedString.Key: config.font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: config.textColor
            ]
        )
        
        let line = CTLineCreateWithAttributedString(attrString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let textWidth = bounds.width
        let textHeight = bounds.height
        
        // Calculate position with stacking
        let origin = calculateOrigin(
            position: position,
            stackIndex: stackIndex,
            textWidth: textWidth,
            textHeight: textHeight,
            config: config
        )
        
        // Draw background box if enabled
        if config.settings.overlayBoxEnabled {
            let boxRect = CGRect(
                x: origin.x - config.boxPadding,
                y: origin.y - config.boxPadding,
                width: textWidth + (config.boxPadding * 2),
                height: textHeight + (config.boxPadding * 2)
            )
            
            context.setFillColor(config.boxColor)
            context.fill(boxRect)
        }
        
        // Draw text
        context.textMatrix = .identity
        context.textPosition = origin
        CTLineDraw(line, context)
    }
    
    private static func calculateOrigin(
        position: BurnInPosition,
        stackIndex: Int,
        textWidth: CGFloat,
        textHeight: CGFloat,
        config: Config
    ) -> CGPoint {
        let lineStep = textHeight + config.lineGap
        let w = config.outputSize.width
        let h = config.outputSize.height
        let m = config.margin
        
        // Calculate base positions for each anchor point
        let x: CGFloat
        let y: CGFloat
        
        switch position {
        case .upperLeft:
            x = m
            y = h - m - textHeight - (CGFloat(stackIndex) * lineStep)
            
        case .upperCenter:
            x = (w - textWidth) / 2
            y = h - m - textHeight - (CGFloat(stackIndex) * lineStep)
            
        case .upperRight:
            x = w - textWidth - m
            y = h - m - textHeight - (CGFloat(stackIndex) * lineStep)
            
        case .middleLeft:
            x = m
            y = (h - textHeight) / 2 - (CGFloat(stackIndex) * lineStep)
            
        case .center:
            x = (w - textWidth) / 2
            y = (h - textHeight) / 2 - (CGFloat(stackIndex) * lineStep)
            
        case .middleRight:
            x = w - textWidth - m
            y = (h - textHeight) / 2 - (CGFloat(stackIndex) * lineStep)
            
        case .lowerLeft:
            x = m
            y = m + (CGFloat(stackIndex) * lineStep)
            
        case .lowerCenter:
            x = (w - textWidth) / 2
            y = m + (CGFloat(stackIndex) * lineStep)
            
        case .lowerRight:
            x = w - textWidth - m
            y = m + (CGFloat(stackIndex) * lineStep)
        }
        
        return CGPoint(x: x, y: y)
    }
    
    // MARK: - Context Creation
    
    private static func createContext(for pixelBuffer: CVPixelBuffer) -> CGContext? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // BGRA format (matches kCVPixelFormatType_32BGRA)
        return CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }
    
    // MARK: - Timecode Calculation
    
    private static func timecodeString(forFrame frameNumber: Int64, config: Config) -> String {
        let startFrame = startFrameOffset(config: config)
        let totalFrames = Int(frameNumber) + startFrame
        
        let fps = config.fps
        let isDrop = abs(fps - 29.97) < 0.01 || abs(fps - 59.94) < 0.01
        
        if isDrop {
            return dropFrameTimecode(frame: totalFrames, fps: fps)
        } else {
            return nonDropTimecode(frame: totalFrames, fps: fps)
        }
    }
    
    private static func nonDropTimecode(frame: Int, fps: Double) -> String {
        let framesPerSec = Int(round(fps))
        let ff = frame % framesPerSec
        let totalSecs = frame / framesPerSec
        let ss = totalSecs % 60
        let mm = (totalSecs / 60) % 60
        let hh = totalSecs / 3600
        return String(format: "%02d:%02d:%02d:%02d", hh, mm, ss, ff)
    }
    
    private static func dropFrameTimecode(frame: Int, fps: Double) -> String {
        // SMPTE drop-frame calculation
        // For 29.97: drop frames 0 and 1 at the start of each minute, except minutes 0, 10, 20, 30, 40, 50
        // For 59.94: drop frames 0, 1, 2, 3 at the start of each minute, except every 10th minute
        
        let is5994 = abs(fps - 59.94) < 0.01
        let framesPerSecond = is5994 ? 60 : 30
        let dropFrames = is5994 ? 4 : 2
        
        // Total frames in one minute (1800 for 29.97, 3600 for 59.94)
        let nominalFramesPerMin = framesPerSecond * 60
        // Actual frames per minute after drops (1798 for 29.97, 3596 for 59.94)
        let actualFramesPerMin = nominalFramesPerMin - dropFrames
        // Frames per 10 minutes (17982 for 29.97, 35964 for 59.94)
        let framesPer10Min = actualFramesPerMin * 9 + nominalFramesPerMin
        
        // Convert frame count to timecode
        var frameNum = frame
        
        // Calculate 10-minute groups
        let d = frameNum / framesPer10Min
        let m = frameNum % framesPer10Min
        
        // Add back dropped frames for the 10-minute groups
        frameNum += dropFrames * 9 * d
        
        // Within the 10-minute group
        if m >= nominalFramesPerMin {
            // After the first minute (which has no drops in a 10-min block)
            let minutesAfterFirst = (m - nominalFramesPerMin) / actualFramesPerMin
            frameNum += dropFrames * (1 + minutesAfterFirst)
        }
        
        // Now convert to HH:MM:SS:FF
        let ff = frameNum % framesPerSecond
        frameNum /= framesPerSecond
        let ss = frameNum % 60
        frameNum /= 60
        let mm = frameNum % 60
        let hh = frameNum / 60
        
        return String(format: "%02d:%02d:%02d;%02d", hh, mm, ss, ff)
    }
    
    // MARK: - Frame Number Helpers
    
    private static func startFrameOffset(config: Config) -> Int {
        guard let tc = config.startTimecode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tc.isEmpty else { return 0 }
        
        // Parse HH:MM:SS:FF or HH:MM:SS;FF
        let cleaned = tc.replacingOccurrences(of: ";", with: ":")
        let parts = cleaned.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 4 else { return 0 }
        
        let (hh, mm, ss, ff) = (parts[0], parts[1], parts[2], parts[3])
        
        let fps = config.fps
        let isDrop = abs(fps - 29.97) < 0.01 || abs(fps - 59.94) < 0.01
        
        if isDrop {
            return dropFrameToFrameNumber(hh: hh, mm: mm, ss: ss, ff: ff, fps: fps)
        } else {
            let framesPerSec = Int(round(fps))
            return ((hh * 3600) + (mm * 60) + ss) * framesPerSec + ff
        }
    }
    
    private static func dropFrameToFrameNumber(hh: Int, mm: Int, ss: Int, ff: Int, fps: Double) -> Int {
        let is5994 = abs(fps - 59.94) < 0.01
        let framesPerSec = is5994 ? 60 : 30
        let dropsPerMin = is5994 ? 4 : 2
        
        let totalMinutes = hh * 60 + mm
        let dropCount = dropsPerMin * (totalMinutes - (totalMinutes / 10))
        
        return ((hh * 3600 + mm * 60 + ss) * framesPerSec + ff) - dropCount
    }
    
    private static func frameNumberWidth(config: Config) -> Int {
        // Calculate total frames in video
        let meta = config.settings.meta
        guard meta.durationSeconds > 0 else {
            return 6 // Default padding
        }
        
        let startFrame = startFrameOffset(config: config)
        let totalFrames = Int(meta.durationSeconds * config.fps) + startFrame
        
        return String(totalFrames).count
    }
    
    // MARK: - Color Helpers
    
    private static func colorFromHex(_ hex: String, alpha: Double) -> CGColor {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                       .replacingOccurrences(of: "#", with: "")
        
        guard clean.count == 6,
              let r = Int(clean.prefix(2), radix: 16),
              let g = Int(clean.dropFirst(2).prefix(2), radix: 16),
              let b = Int(clean.suffix(2), radix: 16)
        else {
            return CGColor(red: 1, green: 1, blue: 1, alpha: alpha)
        }
        
        return CGColor(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: alpha
        )
    }
}
