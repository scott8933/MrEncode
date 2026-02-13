//
//  MetadataService.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/23/25.
//


//
// MARK: - MetadataService.swift
//

import Foundation
import SwiftUI
import Combine
import AVFoundation

/// Handles metadata extraction and caching for media files
class MetadataService: ObservableObject {
    static let shared = MetadataService()
    
    private init() {}
    
    /// Background processing state
    @Published private(set) var backgroundProcessingCount: Int = 0
    @Published private(set) var backgroundProcessingTotal: Int = 0
    
    var isBackgroundProcessing: Bool {
        backgroundProcessingCount > 0
    }
    
    var backgroundProgress: Double {
        guard backgroundProcessingTotal > 0 else { return 0.0 }
        let completed = backgroundProcessingTotal - backgroundProcessingCount
        return Double(completed) / Double(backgroundProcessingTotal)
    }
    
    /// Extract metadata for multiple files in background
    func extractMetadataForFiles(_ urls: [URL], completion: @escaping ([URL: MediaMetadata]) -> Void) {
        DispatchQueue.main.async {
            self.backgroundProcessingCount = urls.count
            self.backgroundProcessingTotal = urls.count
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [URL: MediaMetadata] = [:]
            
            for url in urls {
                let metadata = MetadataExtractor.extract(for: url)
                results[url] = metadata
                
                DispatchQueue.main.async {
                    self.backgroundProcessingCount -= 1
                }
            }
            
            DispatchQueue.main.async {
                self.backgroundProcessingCount = 0
                self.backgroundProcessingTotal = 0
                completion(results)
            }
        }
    }
}
