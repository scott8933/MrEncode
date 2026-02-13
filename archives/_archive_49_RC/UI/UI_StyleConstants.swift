//
//  UI_StyleConstants.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/25/25.
//

import SwiftUI
import AppKit

struct StyleConstants {
    
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

    // Inactive header / toggle labels
    static let headerInactiveLabel = Color.primary.opacity(0.45)
    
    // Footer background
    static let footerBackground = globalBackground
    
    // MARK: - Layout Sizes (Heights, Spacing, Insets)
    
    // Queue (DropZone) panel constraints
    // NOTE: queueMinHeight is the DZ's internal minimum. The top pane's *effective*
    // minimum becomes (topPaneChromeMin + queueMinHeight).
    static let queueMinHeight: CGFloat = 160
    static let queueMaxHeight: CGFloat = 700
    static let queueDefaultHeight: CGFloat = 240
    
    // Make the DZ edge fades taller and stronger
    static let scrollEdgeFadeHeight: CGFloat = 36      // was 22
    static let scrollEdgeFadeOpacity: Double = 0.28    // new (more visible fade)
    
    // Top pane chrome (header + paddings/spacings that sit *above* the DZ)
    // Tune if header layout changes.
    static let topPaneChromeMin: CGFloat = 60
    static var topPaneMinTotalHeight: CGFloat { queueMinHeight + topPaneChromeMin }
    
    // Ensures the Queue Window's bottom stroke isn't visually clipped by the affordance.
    // Keep this tied to the stroke thickness to stay crisp on all scales.
    static let topPaneBottomInset: CGFloat = borderLineWidth
    static let topPaneBottomPadding: CGFloat = panelPadding + (3 * panelCornerRadius)
    
    // Panel spacing and padding rhythm
    static let panelCornerRadius: CGFloat = 8
    static let panelPadding: CGFloat = 12
    static let panelSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 12
    static let rowSpacingDefault: CGFloat = 12
    
    // Footer values
    // Max vertical size for the message area; excess content scrolls inside.
    static let messageAreaMaxHeight: CGFloat = 280
    // Consistent gap under the divider above the messages.
    static let footerTopPadding: CGFloat = panelSpacing

    // Header bar metrics
    static let headerSpacing: CGFloat = 8
    static let headerBarVerticalPadding: CGFloat = 4
    static let headerPickerMinWidth: CGFloat = 160
    static let headerPickerIdealWidth: CGFloat = 220
    static let headerToggleMinWidth: CGFloat = 120
    static let headerModeToggleHeight: CGFloat = 28
    
    // Content margins
    static let contentHorizontalPadding: CGFloat = 16
    static let contentVerticalPadding: CGFloat = 16
    
    // Footer
    static let footerHorizontalPadding: CGFloat = 14
    static let footerBottomPadding: CGFloat = 16
    static let footerStatusMinHeight: CGFloat = 36
    static let footerStatusAlignment: VerticalAlignment = .center
    
    // Message area
    static let messageDetailMaxHeight: CGFloat = 120
    static let messageBottomMargin: CGFloat = 10
    static let copiedToastDuration: Double = 1.6
    
    // UI element sizes (resize handle, etc.)
    static let resizeHandleWidth: CGFloat = 64
    static let resizeHandleHeight: CGFloat = 4
    static let resizeHandleAreaHeight: CGFloat = 16
    
    // Scroll bar / gutter
    static let scrollBarMarginWidth: CGFloat = 14
    static let scrollBarVisualWidth: CGFloat = 8
    
    // Row and list specifications
    static let queueRowHeight: CGFloat = 44
    static let listRowMinHeight: CGFloat = 28
    static let listRowVerticalPadding: CGFloat = 4
    
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
    
    // MARK: - Widths for Controls (centralized to avoid hardcoded literals)
    
    // Compression / container
    static let containerPickerWidth: CGFloat = 168
    
    // NCLC options
    static let nclcPickerWidth: CGFloat = 260
    
    // Overlay options
    static let overlayLabelWidth: CGFloat = 90
    
    // Deadline options
    static let deadlineLabelWidth: CGFloat = 110
    static let deadlinePickerWidth: CGFloat = 240
    static let deadlineFieldWidth: CGFloat = 320
}

// MARK: - Convenience Insets / EdgeInsets

// UI_StyleConstants.swift — add a safety minimum for the middle Options pane
extension StyleConstants {
    static let optionsMinHeight: CGFloat = 120
}

extension StyleConstants {
    // Common panel insets
    static let panelInsets = EdgeInsets(
        top: panelSpacing,
        leading: panelPadding,
        bottom: panelSpacing,
        trailing: panelPadding
    )
    
    // Common list row insets
    static let listRowInsets = EdgeInsets(
        top: listRowVerticalPadding,
        leading: 0,
        bottom: listRowVerticalPadding,
        trailing: panelPadding
    )
}
