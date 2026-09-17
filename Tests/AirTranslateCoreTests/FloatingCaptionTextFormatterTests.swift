import AppKit
import CoreText
import Testing
@testable import AirTranslate

@Suite
@MainActor
struct FloatingCaptionTextFormatterTests {
    @Test
    func floatingCaptionTailWrapsLongEnglishCaptionWhileKeepingRecentLines() {
        let text = """
        This lecture introduces depreciation methods and deferred tax accounting before moving into practice questions for the next topic.
        """

        let caption = text.floatingCaptionTail(maxLines: 3)
        let lines = caption.split(separator: "\n", omittingEmptySubsequences: true)

        #expect(lines.count > 1)
        #expect(lines.count <= 3)
        #expect(caption.contains("deferred tax"))
    }

    @Test
    func floatingCaptionTailKeepsMediumEnglishCaptionOnOneLine() {
        let text = "Why you think we running up for truth hurts, homie."

        let caption = text.floatingCaptionTail(
            maxLines: 2,
            lineWidthUnits: FloatingCaptionTextSize.medium.floatingLineWidthUnits
        )

        #expect(caption == text)
    }

    @Test
    func floatingCaptionTailUsesFontSizeWidthBudget() {
        let text = "Why you think we running up for the truth hurts homie tough love. Tough love keeps the caption readable."

        for size in FloatingCaptionTextSize.allCases {
            let caption = text.floatingCaptionTail(
                maxLines: 4,
                lineWidthUnits: size.floatingLineWidthUnits
            )
            let lines = caption.split(separator: "\n", omittingEmptySubsequences: true)

            #expect(!lines.isEmpty)
            #expect(lines.allSatisfy { $0.floatingCaptionTestDisplayWidth <= size.floatingLineWidthUnits + 0.001 })
        }
    }

    @Test
    func floatingCaptionTailWrapsCJKTextWithoutWhitespace() {
        let text = "감가상각비와이연법인세회계처리를연속해서설명하는강의문장이길어져도자막창에서는읽기좋게나뉘어야합니다감가상각비와이연법인세회계처리를연속해서설명하는강의문장이길어져도자막창에서는읽기좋게나뉘어야합니다"

        let caption = text.floatingCaptionTail(maxLines: 3)
        let lines = caption.split(separator: "\n", omittingEmptySubsequences: true)

        #expect(lines.count > 1)
        #expect(lines.count <= 3)
        #expect(lines.allSatisfy { !$0.isEmpty })
    }

    @Test
    func floatingCaptionTailBreaksAfterCommonSentencePunctuation() {
        let text = "First idea appears. Second idea follows? Third idea lands!"

        let caption = text.floatingCaptionTail(maxLines: 3)

        #expect(caption == """
        First idea appears.
        Second idea follows?
        Third idea lands!
        """)
    }

    @Test(arguments: [376.0, 676.0, 916.0], FloatingCaptionTextSize.allCases)
    func measuredCaptionTailFitsWindowAndPreservesLatestWords(width: Double, size: FloatingCaptionTextSize) {
        let texts = [
            String(repeating: "这是一段持续更新的实时译文，字幕应当保留最新内容。", count: 20) + "最终结果",
            String(repeating: "Wide WWW words keep arriving while the live translation updates. ", count: 20) + "latest result",
            String(repeating: "实时 caption 更新 WWW 和 emoji 👨‍👩‍👧‍👦 continue together. ", count: 20) + "最新 result"
        ]
        let suffixes = ["最终结果", "latest result", "最新 result"]

        for font in [size.primaryNSFont, size.secondaryNSFont] {
            for (text, suffix) in zip(texts, suffixes) {
                for lineLimit in [1, 2, 4] {
                    let caption = text.floatingCaptionTail(maxLines: lineLimit, width: width, font: font)
                    let physicalLines = measuredLines(of: caption, width: width, font: font)

                    #expect(caption.hasSuffix(String(text.suffix(1))))
                    if lineLimit > 1 {
                        #expect(caption.filter { !$0.isWhitespace }.hasSuffix(suffix.filter { !$0.isWhitespace }))
                    }
                    #expect(!physicalLines.isEmpty)
                    #expect(
                        physicalLines.count <= lineLimit,
                        "size=\(size.rawValue), font=\(font.pointSize), width=\(width), lineLimit=\(lineLimit), caption=\(caption.debugDescription)"
                    )
                    for line in physicalLines {
                        #expect(
                            line.width <= width + 0.5 && line.visibleRightEdge <= width + 0.5,
                            "size=\(size.rawValue), font=\(font.fontName) \(font.pointSize), width=\(width), lineLimit=\(lineLimit), measuredWidth=\(line.width), visibleRightEdge=\(line.visibleRightEdge), line=\(line.text.debugDescription), caption=\(caption.debugDescription)"
                        )
                    }
                }
            }
        }
    }

    @Test
    func measuredCaptionTailCorrectsEstimatedLinesThatWouldHideTheLatestText() {
        let font = FloatingCaptionTextSize.medium.primaryNSFont
        let estimatedCaption = String(repeating: "旧", count: 32) + "\n" + String(repeating: "新", count: 32)
        #expect(measuredLineWidths(of: estimatedCaption, width: 676, font: font).count > 2)

        let caption = estimatedCaption.floatingCaptionTail(maxLines: 2, width: 676, font: font)

        #expect(!caption.contains("旧"))
        #expect(caption.replacingOccurrences(of: "\n", with: "") == String(repeating: "新", count: 32))
        #expect(measuredLineWidths(of: caption, width: 676, font: font).count == 2)
    }

    @Test
    func measuredCaptionTailBoundsLongSessionTextBeforeLayout() {
        let text = String(repeating: "历史译文 ", count: 20_000) + "最后一条翻译"
        let font = FloatingCaptionTextSize.medium.primaryNSFont

        let caption = text.floatingCaptionTail(maxLines: 2, width: 376, font: font)

        #expect(caption.hasSuffix("最后一条翻译"))
        #expect(caption.count < 100)
        #expect(measuredLineWidths(of: caption, width: 376, font: font).count <= 2)
    }

    @Test
    func measuredCaptionTailKeepsCJKPunctuationAndLatestLineWithinTheWindow() {
        let font = FloatingCaptionTextSize.medium.primaryNSFont
        // Keep this fixture comfortably within one physical line across CJK
        // fallback fonts. Width-boundary cases are covered by the matrix above.
        let text = "保留最新内容。这是一段持续更新的译文，\n最终结果"

        let caption = text.floatingCaptionTail(maxLines: 2, width: 676, font: font)
        let physicalLines = measuredLines(of: caption, width: 676, font: font)

        #expect(caption == text)
        #expect(physicalLines.count == 2)
        #expect(physicalLines.last?.text == "最终结果")
        for line in physicalLines {
            #expect(
                line.width <= 676 && line.visibleRightEdge <= 676,
                "measuredWidth=\(line.width), visibleRightEdge=\(line.visibleRightEdge), line=\(line.text.debugDescription)"
            )
        }
    }

    private struct MeasuredLine {
        let text: String
        let width: Double
        let visibleRightEdge: Double
    }

    private func measuredLineWidths(of text: String, width: Double, font: NSFont) -> [Double] {
        measuredLines(of: text, width: width, font: font).map(\.width)
    }

    private func measuredLines(of text: String, width: Double, font: NSFont) -> [MeasuredLine] {
        let attributedText = NSAttributedString(string: text, attributes: [.font: font])
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 10_000), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        return lines.map { line in
            let range = CTLineGetStringRange(line)
            let lineText = (text as NSString)
                .substring(with: NSRange(location: range.location, length: range.length))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // CoreText retains a half-em advance after CJK punctuation when a
            // paragraph terminator is included. The terminator adds no ink:
            // measure the actual visible text and its glyph bounds instead.
            let visibleLine = CTLineCreateWithAttributedString(
                NSAttributedString(string: lineText, attributes: [.font: font])
            )
            return MeasuredLine(
                text: lineText,
                width: CTLineGetTypographicBounds(visibleLine, nil, nil, nil),
                visibleRightEdge: CTLineGetBoundsWithOptions(visibleLine, [.useGlyphPathBounds]).maxX
            )
        }
    }
}

private extension Substring {
    var floatingCaptionTestDisplayWidth: Double {
        reduce(0) { width, character in
            if character.isWhitespace {
                return width + 0.45
            }

            guard let scalar = character.unicodeScalars.first else {
                return width + 1
            }

            return width + (scalar.isASCII ? 0.62 : 1)
        }
    }
}
