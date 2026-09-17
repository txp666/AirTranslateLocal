import AppKit
import SwiftUI

enum FloatingCaptionTextSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small:
            AppText.textSizeSmall
        case .medium:
            AppText.textSizeMedium
        case .large:
            AppText.textSizeLarge
        case .extraLarge:
            AppText.textSizeExtraLarge
        }
    }

    var primaryFont: Font {
        .system(size: primaryPointSize, weight: .semibold)
    }

    var secondaryFont: Font {
        .system(size: secondaryPointSize, weight: .medium)
    }

    var primaryNSFont: NSFont {
        .systemFont(ofSize: primaryPointSize, weight: .semibold)
    }

    var secondaryNSFont: NSFont {
        .systemFont(ofSize: secondaryPointSize, weight: .medium)
    }

    var primaryLineHeight: CGFloat {
        primaryPointSize * 1.24
    }

    var secondaryLineHeight: CGFloat {
        secondaryPointSize * 1.28
    }

    var floatingLineWidthUnits: Double {
        switch self {
        case .small:
            39
        case .medium:
            32
        case .large:
            25
        case .extraLarge:
            20
        }
    }

    private var primaryPointSize: CGFloat {
        switch self {
        case .small:
            24
        case .medium:
            30
        case .large:
            38
        case .extraLarge:
            48
        }
    }

    private var secondaryPointSize: CGFloat {
        switch self {
        case .small:
            16
        case .medium:
            20
        case .large:
            24
        case .extraLarge:
            30
        }
    }
}
