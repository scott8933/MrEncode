//
//  UI_StyleConstants.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/25/25.
//

import SwiftUI
import AppKit

struct StyleConstants {
    
    // MARK: - Outer window
    static let windowChromeCornerRadius: CGFloat = 36 // start here

    
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
    
    // MARK: - Link / Clickable Text Colors

    static let linkNormal: Color = .secondary
    static let linkHover: Color = .accentColor
    static let linkDisabled: Color = .gray

    
    // MARK: - Layout Sizes (Heights, Spacing, Insets)
    
    // Queue (DropZone) panel constraints
    // NOTE: queueMinHeight is the DZ's internal minimum. The top pane's *effective*
    // minimum becomes (topPaneChromeMin + queueMinHeight).
    static let queueMinHeight: CGFloat = 200
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
    static let topPaneBottomPadding: CGFloat = panelPaddingV_expanded + (4 * panelCornerRadius)
    
    // Panel spacing and padding rhythm
    static let panelCornerRadius: CGFloat = 22
    
    // Unified card padding system
    static let panelPaddingH: CGFloat = 14          // horizontal padding for all cards
    static let panelPaddingV_folded: CGFloat = 8    // vertical padding when ONLY Presets is visible (8 - bottomed out)
    static let panelPaddingV_expanded: CGFloat = 10 // vertical padding when options are revealed

    static let panelSpacing: CGFloat = 8            // not sure this still adjusts anything
    static let sectionSpacing: CGFloat = 8          // spacing between everything in panelright
    static let rowSpacingDefault: CGFloat = 12      // probably not used any more
    
    // Drop Zone buttons
    static let floatingButtonDiameter: CGFloat = 36
    static let floatingButtonFill = Color(nsColor: .controlBackgroundColor)
    static let floatingButtonShadowColor = Color.black.opacity(0.09)
    static let floatingButtonShadowRadius: CGFloat = 4
    static let floatingButtonShadowOffsetX: CGFloat = 0
    static let floatingButtonShadowOffsetY: CGFloat = 2
    static let queueControlIconSize: CGFloat = 17
    static let queueControlIconWeight: Font.Weight = .medium


    
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
    static let windowMinWidth: CGFloat = 580
    static let windowMinHeight: CGFloat = 500
    
    // Animation durations
    static let hoverAnimationDuration: Double = 0.2
    static let expandAnimationDuration: Double = 0.22
    
    // Border and stroke
    static let borderLineWidth: CGFloat = 1
    static let activeBorderLineWidth: CGFloat = 2
    static let strokeOpacityNormal: Double = 0.25
    static let strokeOpacityActive: Double = 0.8
    
    // MARK: - Widths for Controls (centralized to avoid hardcoded literals)
    
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
        leading: panelPaddingV_expanded,
        bottom: panelSpacing,
        trailing: panelPaddingV_expanded
    )
    
    // Common list row insets
    static let listRowInsets = EdgeInsets(
        top: listRowVerticalPadding,
        leading: 0,
        bottom: listRowVerticalPadding,
        trailing: panelPaddingV_expanded
    )
}
