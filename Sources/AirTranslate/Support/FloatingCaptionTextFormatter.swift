import AppKit

private enum FloatingCaptionTextLayout {
    static let defaultLineWidthUnits = 32.0
    static let scanLineMultiplier = 4

    static func displayWidth(of character: Character) -> Double {
        if character.isWhitespace {
            return 0.45
        }

        guard let scalar = character.unicodeScalars.first else {
            return 1
        }

        return scalar.isASCII ? 0.62 : 1
    }
}

extension String {
    @MainActor
    func floatingCaptionTail(maxLines: Int, width: CGFloat, font: NSFont) -> String {
        let maxLines = max(1, maxLines)
        let scanCharacters = maxLines * 72 * FloatingCaptionTextLayout.scanLineMultiplier
        let scanText = String(boundedSuffix(maxCharacters: scanCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scanText.isEmpty else { return "" }

        // Match the window's font and available width before selecting its tail.
        // Estimated character widths can produce extra physical lines, allowing
        // the view's line limit to truncate the newest translated words.
        let textStorage = NSTextStorage(string: scanText, attributes: [.font: font])
        let layoutManager = NSLayoutManager()
        // Leave room for fractional glyph advances that differ slightly between
        // TextKit's line breaking and SwiftUI's final text layout.
        let textContainer = NSTextContainer(size: NSSize(width: max(1, width - 2), height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let source = scanText as NSString
        var lines: [String] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, range, _ in
            let characterRange = layoutManager.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            let line = source.substring(with: characterRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                lines.append(line)
            }
        }

        return lines.suffix(maxLines).joined(separator: "\n")
    }

    func floatingCaptionTail(
        maxLines: Int,
        lineWidthUnits: Double = FloatingCaptionTextLayout.defaultLineWidthUnits
    ) -> String {
        let maxLines = max(1, maxLines)
        let lineWidthUnits = max(1, lineWidthUnits)
        let trimmedText = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return "" }
        let scanCharacters = maxLines * 72 * FloatingCaptionTextLayout.scanLineMultiplier
        let captionText = trimmedText.floatingCaptionSentenceBreaks()
        let scanText = String(captionText.boundedSuffix(maxCharacters: scanCharacters))

        let logicalLines = scanText.floatingCaptionWrappedLines(
            maxLineWidth: lineWidthUnits
        )

        return logicalLines
            .suffix(maxLines)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func boundedSuffix(maxCharacters: Int) -> Substring {
        guard maxCharacters > 0,
              let start = index(endIndex, offsetBy: -maxCharacters, limitedBy: startIndex)
        else {
            return self[startIndex..<endIndex]
        }

        return self[start..<endIndex]
    }

    private func floatingCaptionSentenceBreaks() -> String {
        replacingOccurrences(
            of: #"(?<!\d)([.!?。！？])\s+(?=\S)"#,
            with: "$1\n",
            options: .regularExpression
        )
    }

    private func floatingCaptionWrappedLines(maxLineWidth: Double) -> [String] {
        components(separatedBy: .newlines)
            .flatMap { paragraph in
                paragraph.floatingCaptionWrappedParagraph(maxLineWidth: maxLineWidth)
            }
            .filter { !$0.isEmpty }
    }

    private func floatingCaptionWrappedParagraph(maxLineWidth: Double) -> [String] {
        let paragraph = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !paragraph.isEmpty else { return [] }

        var lines: [String] = []
        var currentLine = ""
        var currentWidth = 0.0

        for word in paragraph.split(whereSeparator: \.isWhitespace) {
            let word = String(word)
            let wordWidth = word.floatingCaptionDisplayWidth

            if wordWidth > maxLineWidth {
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                    currentLine = ""
                    currentWidth = 0
                }
                lines.append(contentsOf: word.floatingCaptionSplitLongToken(maxLineWidth: maxLineWidth))
                continue
            }

            let separatorWidth = currentLine.isEmpty ? 0 : FloatingCaptionTextLayout.displayWidth(of: " ")
            let nextWidth = currentWidth + separatorWidth + wordWidth
            if !currentLine.isEmpty, nextWidth > maxLineWidth {
                lines.append(currentLine)
                currentLine = word
                currentWidth = wordWidth
            } else {
                if !currentLine.isEmpty {
                    currentLine += " "
                    currentWidth += separatorWidth
                }
                currentLine += word
                currentWidth += wordWidth
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines
    }

    private var floatingCaptionDisplayWidth: Double {
        reduce(0) { width, character in
            width + FloatingCaptionTextLayout.displayWidth(of: character)
        }
    }

    private func floatingCaptionSplitLongToken(maxLineWidth: Double) -> [String] {
        var lines: [String] = []
        var currentLine = ""
        var currentWidth = 0.0

        for character in self {
            let characterWidth = FloatingCaptionTextLayout.displayWidth(of: character)
            if !currentLine.isEmpty, currentWidth + characterWidth > maxLineWidth {
                lines.append(currentLine)
                currentLine = ""
                currentWidth = 0
            }

            currentLine.append(character)
            currentWidth += characterWidth
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines
    }
}
