import AppKit
import SwiftUI

struct CaptionBoardView: View {
    @Bindable var session: TranslationSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalUI.text("实时字幕", "Live captions"))
                        .font(.title2.bold())
                    Text(session.languageSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if session.isStarting {
                    ProgressView().controlSize(.small)
                }
                Text(session.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 280, alignment: .trailing)
            }

            if let line = session.lines.last {
                HStack(alignment: .top, spacing: 16) {
                    TranscriptPane(
                        title: AppText.original,
                        description: LocalUI.text("正在识别的语音", "Recognized speech"),
                        text: line.sourceText,
                        displayText: line.sourceDisplayText,
                        isPrimary: true
                    )
                    TranscriptPane(
                        title: AppText.translation,
                        description: LocalUI.text("本地模型生成的译文", "Translated on this Mac"),
                        text: line.translatedText,
                        displayText: line.translatedDisplayText,
                        isPrimary: false
                    )
                }
            } else {
                ContentUnavailableView {
                    Label(LocalUI.text("让声音变成字幕", "Turn speech into captions"), systemImage: "captions.bubble")
                } description: {
                    Text(LocalUI.text(
                        "选择原文与译文语言，点击“开始翻译”。播放 Mac 音频，或使用麦克风说话。",
                        "Choose your languages and start translating. Play audio on your Mac or speak into the microphone."
                    ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .airTranslateSurface()
            }
        }
        .padding(20)
    }
}

private struct TranscriptPane: View {
    let title: String
    let description: String
    let text: String
    let displayText: String
    let isPrimary: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTextOverflowing = false
    @State private var isReadingBack = false
    @State private var isCopyFeedbackVisible = false
    @State private var copyFeedbackToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 8)

                Button {
                    if copyText() {
                        showCopyFeedback()
                    }
                } label: {
                    Image(systemName: isCopyFeedbackVisible ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isCopyFeedbackVisible ? Color.accentColor : Color.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(TranscriptPaneCopyButtonStyle())
                .controlSize(.small)
                .help(isCopyFeedbackVisible ? AppText.copied : AppText.copyTranscriptPane(title))
                .accessibilityLabel(AppText.copyTranscriptPane(title))
                .accessibilityValue(isCopyFeedbackVisible ? AppText.copied : AppText.copy)
                .disabled(!canCopy)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollableTranscriptText(
                text: displayText,
                weight: isPrimary ? .regular : .medium,
                accessibilityLabel: title,
                isOverflowing: $isTextOverflowing,
                isReadingBack: $isReadingBack
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mask {
                if isTextOverflowing && isReadingBack {
                    TranscriptScrollFadeMask()
                } else {
                    Rectangle()
                }
            }
        }
        .padding(14)
        .frame(minHeight: 240, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .airTranslateSurface(isEmphasized: !isPrimary)
        .task(id: copyFeedbackToken) {
            guard isCopyFeedbackVisible else { return }

            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }

            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                isCopyFeedbackVisible = false
            }
        }
    }

    private var canCopy: Bool {
        text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
            && text != AppText.translating
    }

    private func copyText() -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, trimmedText != AppText.translating else { return false }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmedText, forType: .string)
        return true
    }

    private func showCopyFeedback() {
        copyFeedbackToken += 1

        withAnimation(reduceMotion ? nil : .snappy(duration: 0.16)) {
            isCopyFeedbackVisible = true
        }
    }
}

private struct TranscriptPaneCopyButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.88 : 1))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct TranscriptScrollFadeMask: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)

            Rectangle()
                .fill(.black)

            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)
        }
    }
}

private struct ScrollableTranscriptText: NSViewRepresentable {
    let text: String
    let weight: NSFont.Weight
    let accessibilityLabel: String
    @Binding var isOverflowing: Bool
    @Binding var isReadingBack: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isOverflowing: $isOverflowing, isReadingBack: $isReadingBack)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.setAccessibilityLabel(accessibilityLabel)

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: weight)
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.autoresizingMask = [.width]
        textView.setAccessibilityLabel(accessibilityLabel)

        scrollView.documentView = textView
        context.coordinator.attach(to: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let contentWidth = scrollView.contentSize.width
        let textChanged = textView.string != text
        let widthChanged = abs(context.coordinator.lastContentWidth - contentWidth) > 0.5
        let weightChanged = context.coordinator.lastWeight != weight
        guard textChanged || widthChanged || weightChanged else { return }

        let shouldStayPinnedToBottom = isPinnedToBottom(scrollView)
        if textChanged {
            textView.string = text
        }

        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: weight)
        textView.textColor = .labelColor
        scrollView.setAccessibilityLabel(accessibilityLabel)
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.textContainer?.containerSize = NSSize(
            width: contentWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        let documentHeight = updateDocumentSize(textView, in: scrollView)
        context.coordinator.recordLayoutInput(
            contentWidth: contentWidth,
            weight: weight
        )
        let isOverflowing = documentHeight > scrollView.contentSize.height + 1
        context.coordinator.updateState(
            isOverflowing: isOverflowing,
            isReadingBack: isOverflowing && !shouldStayPinnedToBottom
        )

        if shouldStayPinnedToBottom {
            textView.scrollToEndOfDocument(nil)
            context.coordinator.updateState(isOverflowing: isOverflowing, isReadingBack: false)
        }
    }

    private func updateDocumentSize(_ textView: NSTextView, in scrollView: NSScrollView) -> CGFloat {
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager
        else {
            textView.frame.size = scrollView.contentSize
            return scrollView.contentSize.height
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2
        textView.frame.size = NSSize(
            width: scrollView.contentSize.width,
            height: max(scrollView.contentSize.height, usedHeight)
        )
        return usedHeight
    }

    private func isPinnedToBottom(_ scrollView: NSScrollView) -> Bool {
        guard let documentView = scrollView.documentView else { return true }

        let visibleMaxY = scrollView.contentView.bounds.maxY
        let documentHeight = documentView.bounds.height
        return documentHeight <= scrollView.contentSize.height || documentHeight - visibleMaxY < 24
    }

    @MainActor
    final class Coordinator: NSObject {
        private var isOverflowing: Binding<Bool>
        private var isReadingBack: Binding<Bool>
        private weak var scrollView: NSScrollView?
        var lastContentWidth: CGFloat = -1
        var lastWeight: NSFont.Weight?

        init(isOverflowing: Binding<Bool>, isReadingBack: Binding<Bool>) {
            self.isOverflowing = isOverflowing
            self.isReadingBack = isReadingBack
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(to scrollView: NSScrollView) {
            self.scrollView = scrollView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(contentBoundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func updateState(isOverflowing: Bool, isReadingBack: Bool) {
            guard self.isOverflowing.wrappedValue != isOverflowing
                || self.isReadingBack.wrappedValue != isReadingBack
            else {
                return
            }

            self.isOverflowing.wrappedValue = isOverflowing
            self.isReadingBack.wrappedValue = isReadingBack
        }

        func recordLayoutInput(contentWidth: CGFloat, weight: NSFont.Weight) {
            lastContentWidth = contentWidth
            lastWeight = weight
        }

        @objc private func contentBoundsDidChange() {
            guard let scrollView else { return }
            let isOverflowing = hasOverflow(scrollView)
            updateState(
                isOverflowing: isOverflowing,
                isReadingBack: isOverflowing && !isPinnedToBottom(scrollView)
            )
        }

        private func hasOverflow(_ scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else { return false }
            return documentView.bounds.height > scrollView.contentSize.height + 1
        }

        private func isPinnedToBottom(_ scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else { return true }

            let visibleMaxY = scrollView.contentView.bounds.maxY
            let documentHeight = documentView.bounds.height
            return documentHeight <= scrollView.contentSize.height || documentHeight - visibleMaxY < 24
        }
    }
}
