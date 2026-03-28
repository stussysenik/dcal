/* SMPTE-compliant achromatic design tokens.
   All surface colors are achromatic (R=G=B) per SMPTE ST 2080-3
   guidelines for color-critical monitoring environments.

   Chromatic color is reserved exclusively for data communication:
   RGB channel indicators, pass/fail status, and calibration targets.
   This prevents the UI itself from biasing the operator's color perception. */

import SwiftUI

extension Color {
    // MARK: - Achromatic Surfaces (R=G=B)

    /// Deepest background — panel chrome, window frame
    static let dcSurface0 = Color(white: 0x1A / 255.0)   // #1A1A1A
    /// Primary content background — main popover fill
    static let dcSurface1 = Color(white: 0x24 / 255.0)   // #242424
    /// Elevated surface — cards, grouped sections
    static let dcSurface2 = Color(white: 0x2E / 255.0)   // #2E2E2E
    /// Highest elevation — interactive elements, hover states
    static let dcSurface3 = Color(white: 0x38 / 255.0)   // #383838

    // MARK: - Text Hierarchy

    static let dcTextPrimary   = Color(white: 0xEB / 255.0) // ~92% white
    static let dcTextSecondary = Color(white: 0xA3 / 255.0) // ~64% white
    static let dcTextTertiary  = Color(white: 0x6B / 255.0) // ~42% white

    // MARK: - Functional Colors (data communication only)

    /// Red channel indicator — desaturated to avoid biasing color perception
    static let dcChannelR = Color(red: 0.77, green: 0.44, blue: 0.44)
    /// Green channel indicator
    static let dcChannelG = Color(red: 0.42, green: 0.69, blue: 0.42)
    /// Blue channel indicator
    static let dcChannelB = Color(red: 0.42, green: 0.56, blue: 0.77)
    /// Calibration pass / within tolerance
    static let dcPass = Color(red: 0.42, green: 0.69, blue: 0.42)
    /// Warning / approaching tolerance limit
    static let dcWarn = Color(red: 0.77, green: 0.66, blue: 0.31)
}

extension Font {
    /// Section headings (13pt semibold)
    static let dcHeading = Font.system(size: 13, weight: .semibold)
    /// Form labels and descriptions (11pt regular)
    static let dcLabel = Font.system(size: 11, weight: .regular)
    /// Tertiary information, timestamps (10pt regular)
    static let dcCaption = Font.system(size: 10, weight: .regular)
    /// Section divider labels (9pt semibold, typically uppercased)
    static let dcSectionHeader = Font.system(size: 9, weight: .semibold)
    /// Large numeric readouts — gamma values, scores (20pt mono)
    static let dcNumericLarge = Font.system(size: 20, weight: .medium, design: .monospaced)
    /// Medium numeric readouts — channel values (13pt mono)
    static let dcNumericMedium = Font.system(size: 13, weight: .medium, design: .monospaced)
    /// Small numeric readouts — slider values, coordinates (11pt mono)
    static let dcNumericSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
}

/// Layout constants on an 8pt grid.
enum DCLayout {
    static let panelWidth: CGFloat = 340
    static let contentPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 12
}
