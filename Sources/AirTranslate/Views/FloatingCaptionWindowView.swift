import AppKit
import SwiftUI

struct FloatingCaptionWindowView: View {
    @Bindable var session: TranslationSessionStore
    @State private var contentWidth: CGFloat = 676

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { width in
                contentWidth = width
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background {
                if hasVisibleCaptionText, session.showsFloatingCaptionBackground {
                    RoundedRectangle(cornerRadius: AirTranslateDesign.surfaceRadius, style: .continuous)
                        .fill(.black.opacity(0.76))
                        .overlay {
                            RoundedRectangle(cornerRadius: AirTranslateDesign.surfaceRadius, style: .continuous)
                                .strokeBorder(.white.opacity(0.12))
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 420, idealWidth: 720, maxWidth: 960, minHeight: 90, idealHeight: preferredHeight, maxHeight: preferredHeight)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
        .overlay {
            FloatingCaptionDragSurface()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            FloatingWindowConfigurator(
                preferredContentHeight: preferredHeight,
                keepsAboveOtherWindows: session.keepsFloatingCaptionAboveOtherWindows
            )
        )
    }

    @ViewBuilder
    private var content: some View {
        if !session.isFloatingCaptionHiddenAfterSilence {
            switch session.floatingCaptionDisplayMode {
            case .original:
                subtitleText(sourceText, font: session.floatingCaptionTextSize.primaryNSFont)
            case .originalAndTranslation:
                if !sourceText.isEmpty {
                    subtitleText(sourceText, font: session.floatingCaptionTextSize.secondaryNSFont)
                        .opacity(0.82)
                    if !translationText.isEmpty {
                        subtitleText(translationText, font: session.floatingCaptionTextSize.primaryNSFont)
                    } else {
                        subtitleText(" ", font: session.floatingCaptionTextSize.primaryNSFont)
                            .opacity(0)
                    }
                } else if !translationText.isEmpty {
                    subtitleText(translationText, font: session.floatingCaptionTextSize.primaryNSFont)
                } else {
                    subtitleText(AppText.noFloatingCaptionsYet, font: session.floatingCaptionTextSize.primaryNSFont)
                }
            case .translation:
                if !translationText.isEmpty {
                    subtitleText(translationText, font: session.floatingCaptionTextSize.primaryNSFont)
                } else if sourceText.isEmpty {
                    subtitleText(AppText.noFloatingCaptionsYet, font: session.floatingCaptionTextSize.primaryNSFont)
                }
            }
        }
    }

    private var sourceText: String {
        session.floatingSourceText
    }

    private var translationText: String {
        session.floatingTranslationText
    }

    private var hasVisibleCaptionText: Bool {
        if session.isFloatingCaptionHiddenAfterSilence {
            return false
        }

        return switch session.floatingCaptionDisplayMode {
        case .original, .originalAndTranslation:
            true
        case .translation:
            !translationText.isEmpty || sourceText.isEmpty
        }
    }

    private var lineLimit: Int {
        session.floatingCaptionLineCount.rawValue
    }

    private var preferredHeight: CGFloat {
        let textSize = session.floatingCaptionTextSize
        let lineCount = CGFloat(lineLimit)
        let primaryHeight = textSize.primaryLineHeight * lineCount + CGFloat(lineLimit - 1) * 5
        let secondaryHeight = textSize.secondaryLineHeight * lineCount + CGFloat(lineLimit - 1) * 5
        let textHeight: CGFloat

        switch session.floatingCaptionDisplayMode {
        case .original, .translation:
            textHeight = primaryHeight
        case .originalAndTranslation:
            textHeight = primaryHeight + secondaryHeight + 8
        }

        return min(max(90, textHeight + 28), 720)
    }

    private func subtitleText(_ text: String, font: NSFont) -> some View {
        let displayText = text.isEmpty ? AppText.noFloatingCaptionsYet : text
        let caption = displayText.floatingCaptionTail(maxLines: lineLimit, width: contentWidth, font: font)

        return Text(caption.isEmpty ? " " : caption)
            .font(Font(font))
            .foregroundStyle(.white)
            .textSelection(.disabled)
            .lineLimit(lineLimit)
            .truncationMode(.head)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .lineSpacing(5)
            .shadow(color: .black.opacity(0.95), radius: 3, x: 0, y: 1)
            .shadow(color: .black.opacity(0.65), radius: 8, x: 0, y: 2)
    }
}
