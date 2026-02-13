//
//  AppColors.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/25/25.
//

import SwiftUI
import AppKit

struct AppColors {
    
    // MARK: - Base Colors
    
    // Global background - main app canvas
    static let globalBackground: Color = {
        let nsColor = NSColor.controlBackgroundColor
        let darkerColor = nsColor.blended(withFraction: 0.035, of: NSColor.black) ?? nsColor
        return Color(darkerColor)
    }()
    
    // Control background - standard system background
    static let controlBackgroundColor: Color = {
        let nsColor = NSColor.controlBackgroundColor
        return Color(nsColor)
    }()
    
    // MARK: - Applied Colors
    
    // Panel backgrounds - main content areas
    static let panelBackground = globalBackground
    
    // Panel fills - content inside panels
    static let panelFill = controlBackgroundColor
    
    // Footer background
    static let footerBackground = globalBackground
    
    // MARK: - Layout Sizes
    
    // Queue panel constraints
    static let queueMinHeight: CGFloat = 60
    static let queueMaxHeight: CGFloat = 700
    static let queueDefaultHeight: CGFloat = 280
    
    // Panel spacing and padding
    static let panelCornerRadius: CGFloat = 8
    static let panelPadding: CGFloat = 12
    static let panelSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 12
    
    // UI element sizes
    static let resizeHandleWidth: CGFloat = 64
    static let resizeHandleHeight: CGFloat = 4
    static let resizeHandleAreaHeight: CGFloat = 16
    
    // Scroll bar dimensions
    static let scrollBarMarginWidth: CGFloat = 14
    static let scrollBarVisualWidth: CGFloat = 8
    
    // Row and list specifications
    static let queueRowHeight: CGFloat = 44
    static let listRowMinHeight: CGFloat = 28
    static let listRowVerticalPadding: CGFloat = 4
    
    // Content margins
    static let contentHorizontalPadding: CGFloat = 16
    static let contentVerticalPadding: CGFloat = 16
    static let footerHorizontalPadding: CGFloat = 14
    static let footerBottomPadding: CGFloat = 16
    
    // Window constraints
    static let windowMinWidth: CGFloat = 640
    static let windowMinHeight: CGFloat = 720
    
    // Animation durations
    static let hoverAnimationDuration: Double = 0.2
    static let expandAnimationDuration: Double = 0.22
    
    // Border and stroke
    static let borderLineWidth: CGFloat = 1
    static let activeBorderLineWidth: CGFloat = 2
    static let strokeOpacityNormal: Double = 0.25
    static let strokeOpacityActive: Double = 0.8
}

// MARK: - Convenience Extensions

extension AppColors {
    // Commonly used padding values
    static let panelInsets = EdgeInsets(
        top: panelSpacing,
        leading: panelPadding,
        bottom: panelSpacing,
        trailing: panelPadding
    )
    
    static let listRowInsets = EdgeInsets(
        top: listRowVerticalPadding,
        leading: 0,
        bottom: listRowVerticalPadding,
        trailing: panelPadding
    )
    
    // Common spacing values
    static let headerSpacing: CGFloat = 8
    static let buttonSpacing: CGFloat = 8
    static let controlSpacing: CGFloat = 12
}
