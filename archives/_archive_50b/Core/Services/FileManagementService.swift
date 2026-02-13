//
//  FileManagementService.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/23/25.
//


//
// MARK: - FileManagementService.swift
//

import Foundation
import SwiftUI

/// Handles file operations and queue management
class FileManagementService: ObservableObject {
    static let shared = FileManagementService()
    
    private init() {}
    
    /// Build cached source line for display
    func buildCachedSrcLine(for item: MediaItem) -> String {
        let url = item.url
        let meta = item.meta
        
        var parts: [String] = []
        
        // Duration
        if meta.durationSeconds > 0 {
            let mins = Int(meta.durationSeconds / 60)
            let secs = Int(meta.durationSeconds.truncatingRemainder(dividingBy: 60))
            parts.append("\(mins):\(String(format: "%02d", secs))")
        }
        
        // FPS
        if let fps = meta.nominalFPS, fps > 0 {
            parts.append("\(String(format: "%.2f", fps)) fps")
        }
        
        // File size
        if let size = item.cachedFileSize {
            let mb = Double(size) / 1_000_000
            if mb >= 1000 {
                parts.append(String(format: "%.1f GB", mb / 1000))
            } else {
                parts.append(String(format: "%.0f MB", mb))
            }
        }
        
        // NCLC info
        if let p = meta.colorPrimaries, 
           let t = meta.transferFunction,
           let m = meta.ycbcrMatrix,
           let desc = nclcDescription(p: p, t: t, m: m) {
            parts.append(desc)
        }
        
        return parts.isEmpty ? url.lastPathComponent : parts.joined(separator: " • ")
    }
    
    /// Build cached destination line for display  
    func buildCachedDstLine(for item: MediaItem, settings: Settings) -> String {
        let url = item.url
        let meta = item.meta
        
        // Generate proper estimates
        let estWallTime: Double? = EncodeTimeEstimator.estimateSeconds(
            url: url,
            meta: meta,
            settings: settings,
            runMode: settings.runMode
        )
        
        var parts: [String] = []
        
        // Add size estimate
        if let est = OutputEstimator.estimate(url: url, meta: meta, settings: settings) {
            let mb = est.estBytes / 1_000_000.0
            if mb >= 1000 {
                parts.append(String(format: "%.1f GB", mb / 1000.0))
            } else {
                parts.append(String(format: "%.1f MB", mb))
            }
        }
        
        // Add time estimate
        if let wallTime = estWallTime, wallTime.isFinite, wallTime > 0 {
            parts.append("Est. Render Time: \(EncodeTimeEstimator.formatTime(wallTime))")
        }
        
        return parts.isEmpty ? "Estimating..." : parts.joined(separator: " • ")
    }
    
    /// Get file size for caching
    func getFileSize(for url: URL) -> Int64? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attrs[.size] as? NSNumber)?.int64Value
        } catch {
            return nil
        }
    }
    
    // MARK: - Private Helpers
    
    private func nclcDescription(p: String, t: String, m: String) -> String? {
        // Convert to integers for comparison
        guard let pInt = Int(p), let tInt = Int(t), let mInt = Int(m) else { return nil }
        
        switch (pInt, tInt, mInt) {
        case (1, 1, 1):   return "Rec.709"
        case (1, 13, 1):  return "Rec.709 (sRGB TF)"
        case (12, 1, 1):  return "Display P3"
        case (12, 13, 1): return "Display P3 (sRGB TF)"
        case (9, 16, 9):  return "BT.2020 PQ (HDR10)"
        case (9, 18, 9):  return "BT.2020 HLG"
        case (9, 1, 9):   return "BT.2020 (709 TF)"
        case (6, 1, 6):   return "BT.601 NTSC"
        case (5, 1, 5):   return "BT.601 PAL"
        default:          return nil
        }
    }
}
