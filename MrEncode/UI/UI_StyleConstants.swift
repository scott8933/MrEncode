//
//  UI_StyleConstants.swift
//  MrEncode
//
//  Style system tokens.
//  Organized for maintainability: Colors → Typography → Spacing → Sizes → Borders → Motion → Insets.
//
//  IMPORTANT USAGE PATTERN (recommended):
//    @Environment(\.colorScheme) private var colorScheme
//    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }
//    ...then use C.bgApp, C.bgPanel, C.strokeSubtle, etc.
//
//  Theme override support:
//    - Store a user selection (system/light/dark) in your Settings.
//    - Apply .preferredColorScheme(...) at the root (ContentView or WindowGroup).
//

import SwiftUI
import AppKit

struct StyleConstants {

    // MARK: - Theme

    enum ThemeSelection: String, Codable, CaseIterable {
        case system
        case light
        case dark

        func preferredColorScheme() -> ColorScheme? {
            switch self {
            case .system: return nil
            case .light:  return .light
            case .dark:   return .dark
            }
        }
    }

    // MARK: - Colors (Semantic)

    struct Colors {
        // Base surfaces
        let bgApp: Color
        let bgDropZone: Color
        let bgPanel: Color
        let bgInset: Color
        let panelWash: Color

        // Strokes / dividers
        let strokeDropZone: Color
        let strokeSubtle: Color
        let strokeHairline: Color

        // Text
        let textPrimary: Color
        let textSecondary: Color
        let textTertiary: Color
        let textDisabled: Color

        // Accent
        let accent: Color
        let accentSoft: Color

        // Interaction
        let selectionFill: Color
        let hoverFill: Color

        // Status
        let statusGood: Color
        let statusWarning: Color
        let statusError: Color
        let statusInfo: Color

        // Links / clickable text
        let linkNormal: Color
        let linkHover: Color
        let linkDisabled: Color
        
        // Buttons and Surfaces
        let bgPlaybar: Color
        let playbarShadow: Color
        let floatingButtonFill: Color
        let floatingButtonShadow: Color
        let floatingControlIcon: Color

        // Modified state accents (Panel Headers)
        let modifiedAccent: Color                 // used for "(Modified)" suffix + misc
        let headerModifiedLabel: Color            // orange-tinted header when panel is open
        let headerModifiedInactiveLabel: Color    // orange-tinted header when panel is closed
        let headerInactiveLabel: Color
        let presetTitleHover: Color
        
        // Text inputs (TextField / TextEditor wrappers)
        let inputBackground: Color
        let inputBorder: Color
    }
    

    /// Light palette
    private static let paletteLight = Colors(
        bgApp:      Color(hex: 0xEEEEEE),
        bgDropZone: Color(hex: 0xF9F9F9),
        bgPanel:    Color(hex: 0xEEEEEE),
        bgInset:    Color(hex: 0xEEEEEE),
        panelWash:  Color(hex: 0xEEEEEE).opacity(0.0),

        // Strokes
        strokeDropZone: Color.black.opacity(0.16),
        strokeSubtle:   Color.black.opacity(0.16),
        strokeHairline: Color.black.opacity(0.10),

        textPrimary:   Color.black.opacity(0.88),
        textSecondary: Color.black.opacity(0.62),
        textTertiary:  Color.black.opacity(0.52),
        textDisabled:  Color.black.opacity(0.32),

        accent:     Color(hex: 0x2F7CFF),
        accentSoft: Color(hex: 0x2F7CFF).opacity(0.18),

        selectionFill: Color.black.opacity(0.05),
        hoverFill:     Color.black.opacity(0.035),

        statusGood:    Color(hex: 0x21B26B),
        statusWarning: Color(hex: 0xF2A63B),
        statusError:   Color(hex: 0xE45757),
        statusInfo:    Color(hex: 0x2F7CFF),

        // Links: keep conservative; hover uses accent
        linkNormal:   Color.black.opacity(0.62),
        linkHover:    Color(hex: 0x2F7CFF),
        linkDisabled: Color.black.opacity(0.32),
        
        // Buttons and Surfaces:
        bgPlaybar: Color.white,
        playbarShadow: Color.black.opacity(0.12),
        floatingButtonFill: Color.black.opacity(0.06),
        floatingButtonShadow: Color.black.opacity(0.18),
        floatingControlIcon: Color.black.opacity(0.52),

        // Panel Headers
        modifiedAccent: Color(hex: 0xEC9418), // matches statusWarning hue
        headerModifiedLabel: Color(hex: 0xEC9418).opacity(1.00),
        headerModifiedInactiveLabel: Color(hex: 0xEC9418).opacity(0.60),
        headerInactiveLabel: Color.black.opacity(0.35),
        presetTitleHover: Color(hex: 0x2F7CFF),
        
        inputBackground: Color(hex: 0xE6E6E6),
        inputBorder:     Color.black.opacity(0.10),
    )

    /// Dark palette (manual)
    private static let paletteDark = Colors(
        bgApp:   Color(hex: 0x121316),
        bgDropZone: Color(hex: 0x242424),
        bgPanel: Color(hex: 0x1F1F1F),
        bgInset: Color(hex: 0x14161A),
        panelWash: Color.white.opacity(0.00),

        strokeDropZone: Color.white.opacity(0.10),
        strokeSubtle:   Color.white.opacity(0.10),
        strokeHairline: Color.white.opacity(0.06),

        textPrimary:   Color.white.opacity(0.90),
        textSecondary: Color.white.opacity(0.66),
        textTertiary:  Color.white.opacity(0.52),
        textDisabled:  Color.white.opacity(0.32),

        accent:     Color(hex: 0x2F7CFF),
        accentSoft: Color(hex: 0x2F7CFF).opacity(0.20),

        selectionFill: Color.white.opacity(0.08),
        hoverFill:     Color.white.opacity(0.06),

        statusGood:    Color(hex: 0x21B26B),
        statusWarning: Color(hex: 0xF2A63B),
        statusError:   Color(hex: 0xE45757),
        statusInfo:    Color(hex: 0x2F7CFF),

        linkNormal:   Color.white.opacity(0.70),
        linkHover:    Color(hex: 0x2F7CFF),
        linkDisabled: Color.white.opacity(0.32),
        
        bgPlaybar: Color.white.opacity(0.08),
        playbarShadow: Color.black.opacity(0.80),
        floatingButtonFill: Color.white.opacity(0.90),
        floatingButtonShadow: Color.black.opacity(0.80),
        floatingControlIcon: Color.white.opacity(0.52),

        modifiedAccent: Color(hex: 0xF2A63B),
        headerModifiedLabel: Color(hex: 0xF2A63B).opacity(0.95),
        headerModifiedInactiveLabel: Color(hex: 0xF2A63B).opacity(0.70),
        headerInactiveLabel: Color.white.opacity(0.35),
        presetTitleHover: Color(hex: 0x2F7CFF),
        
        inputBackground: Color.white.opacity(0.08),
        inputBorder:     Color.white.opacity(0.14),
    )

    /// Resolve semantic colors for the current system ColorScheme.
    static func colors(for scheme: ColorScheme) -> Colors {
        scheme == .dark ? paletteDark : paletteLight
    }

    // MARK: - Back-compat aliases (optional during migration)
    // If you want, you can keep these for a short period while doing the global sweep,
    // but they cannot respond to per-view ColorScheme without passing scheme in.
    //
    // Prefer migrating call sites to use colors(for:).

    // MARK: - Typography

    enum Typography {
        static let header: Font = .headline
        static let section: Font = .subheadline.weight(.semibold)
        static let body: Font = .body
        static let caption: Font = .caption

        // Icons
        static let queueControlIconSize: CGFloat = 17
        static let queueControlIconWeight: Font.Weight = .medium
    }

    // MARK: - Spacing

    enum Spacing {
        // Content margins, main App
        static let contentHorizontalPadding: CGFloat = 16
        static let contentVerticalPadding: CGFloat = 16

        // Panel spacing and padding rhythm
        static let panelCornerRadius: CGFloat = 22

        // Unified card padding system
        static let panelPaddingH: CGFloat = 14
        static let panelPaddingV_folded: CGFloat = 8
        static let panelPaddingV_expanded: CGFloat = 10

        // Panel inner contents left padding
        static let leadingPadding: CGFloat = 24  // Originally was 12

        static let panelSpacing: CGFloat = 8     // distance between header and the rest
        static let sectionSpacing: CGFloat = 8   // distance between panels AND items within panels

        // Header bar metrics
        static let headerSpacing: CGFloat = 8   // horizontal chevron to headline   >>>only in Presets<<<
        static let headerBarVerticalPadding: CGFloat = 4  // I don't know what this does

        // Footer
        static let footerHorizontalPadding: CGFloat = 20
        static let footerBottomPadding: CGFloat = 16
        static let footerTopPadding: CGFloat = panelSpacing
        static let footerStatusAlignment: VerticalAlignment = .firstTextBaseline
        static let messageBottomMargin: CGFloat = 10

        // Rows / lists
        static let listRowVerticalPadding: CGFloat = 4    // Drop Zone row vertical pad
        static let rowSpacingDefault: CGFloat = 12        // keep if still referenced
        
        // Scroll bar
        static let scrollBarMarginWidth: CGFloat = 14  // right side margin
        static let scrollBarVisualWidth: CGFloat = 4   // left side margin
    }

    // MARK: - Sizes

    enum Sizes {
        // Outer window
        static let windowChromeCornerRadius: CGFloat = 36

        // Queue (DropZone) panel constraints
        static let queueMinHeight: CGFloat = 200
        static let queueMaxHeight: CGFloat = 700
        static let queueDefaultHeight: CGFloat = 240

        // Make the DZ edge fades taller and stronger
        static let scrollEdgeFadeHeight: CGFloat = 36
        static let scrollEdgeFadeOpacity: Double = 0.28

        // Top pane chrome (header + paddings/spacings that sit *above* the DZ)
        static let topPaneChromeMin: CGFloat = 60
        static var topPaneMinTotalHeight: CGFloat { queueMinHeight + topPaneChromeMin }

        // Ensures the Queue Window's bottom stroke isn't visually clipped by the affordance.
        static var topPaneBottomInset: CGFloat { Borders.borderLineWidth }
        static let topPaneBottomPadding: CGFloat = Spacing.panelPaddingV_expanded + (4 * Spacing.panelCornerRadius)

        // Drop Zone buttons
        static let floatingButtonDiameter: CGFloat = 36
        static let floatingButtonShadowRadius: CGFloat = 4
        static let floatingButtonShadowOffsetX: CGFloat = 0
        static let floatingButtonShadowOffsetY: CGFloat = 2

        // Footer values
        static let messageAreaMaxHeight: CGFloat = 280
        static let footerStatusMinHeight: CGFloat = 36
        static let messageDetailMaxHeight: CGFloat = 120
        static let messageBottomMargin: CGFloat = 10
        static let copiedToastDuration: Double = 1.6

        // UI element sizes (resize handle, etc.)
        static let resizeHandleWidth: CGFloat = 64
        static let resizeHandleHeight: CGFloat = 4
        static let resizeHandleAreaHeight: CGFloat = 16

        // Row and list specifications
        static let queueRowHeight: CGFloat = 44
        static let listRowMinHeight: CGFloat = 28

        // Window constraints
        static let windowMinWidth: CGFloat = 580
        static let windowMinHeight: CGFloat = 500

        // Header picker sizing
        static let headerPickerMinWidth: CGFloat = 160
        static let headerPickerIdealWidth: CGFloat = 220
        static let headerToggleMinWidth: CGFloat = 120
        static let headerModeToggleHeight: CGFloat = 28

        // Centralized widths
        static let nclcPickerWidth: CGFloat = 260
        static let overlayLabelWidth: CGFloat = 90
        static let deadlineLabelWidth: CGFloat = 110
        static let deadlinePickerWidth: CGFloat = 240
        static let deadlineFieldWidth: CGFloat = 320
    }

    // MARK: - Borders / Strokes

    enum Borders {
        static let borderLineWidth: CGFloat = 1
        static let activeBorderLineWidth: CGFloat = 2

        // Keep these if older code still references them;
        // new code should use Colors.strokeSubtle/hairline directly.
        static let strokeOpacityNormal: Double = 0.25
        static let strokeOpacityActive: Double = 0.8
    }

    // MARK: - Motion

    enum Motion {
        static let hoverAnimationDuration: Double = 0.2
        static let expandAnimationDuration: Double = 0.22
        static let copiedToastDuration: Double = 1.6
    }

    // MARK: - Options pane min height (kept from your extension)
    static let optionsMinHeight: CGFloat = 120

    // MARK: - Insets (EdgeInsets)

    static var panelInsets: EdgeInsets {
        EdgeInsets(
            top: Spacing.panelSpacing,
            leading: Spacing.leadingPadding,   // fixed from prior “V_expanded” misuse
            bottom: Spacing.panelSpacing,
            trailing: Spacing.leadingPadding
        )
    }

    static var listRowInsets: EdgeInsets {
        EdgeInsets(
            top: Spacing.listRowVerticalPadding,
            leading: 0,
            bottom: Spacing.listRowVerticalPadding,
            trailing: Spacing.panelPaddingV_expanded
        )
    }
}


// MARK: - HeaderHelper

extension StyleConstants.Colors {

    /// Canonical panel header color resolver
    func panelHeaderLabel(isExpanded: Bool, isModified: Bool) -> Color {
        if isExpanded {
            return isModified ? headerModifiedLabel : textPrimary
        } else {
            return isModified ? headerModifiedInactiveLabel : headerInactiveLabel
        }
    }
}


// MARK: - Helpers

private extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}


// MARK: - Modifier for EditText box backgrouns

extension View {
    func panelTextFieldStyle(_ C: StyleConstants.Colors) -> some View {
        self
            .textFieldStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .foregroundColor(C.textPrimary)
            .background(C.inputBackground)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(C.inputBorder, lineWidth: 1)
            )
    }
}

