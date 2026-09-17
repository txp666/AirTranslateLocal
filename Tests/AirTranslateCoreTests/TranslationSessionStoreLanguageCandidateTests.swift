import Foundation
import Testing
@testable import AirTranslate

@Suite
struct TranslationSessionStoreLanguageCandidateTests {
    @Test
    func longSessionCaptionLineTrimsDisplayOnly() {
        let text = (1...500)
            .map { "Live transcript line \($0) keeps accumulating during a long session." }
            .joined(separator: "\n")
        let line = CaptionLine(
            sourceText: text,
            translatedText: text,
            createdAt: Date(),
            isFinal: false,
            usesLongSessionDisplay: true
        )

        #expect(line.sourceText == text)
        #expect(line.translatedText == text)
        #expect(line.sourceDisplayText != text)
        #expect(line.translatedDisplayText != text)
        #expect(line.sourceDisplayText.hasPrefix("..."))
        #expect(line.translatedDisplayText.hasPrefix("..."))
    }

    @Test
    func veryLargeCaptionLineTrimsDisplayEvenInStandardMode() {
        let text = (1...500)
            .map { "Standard session can still receive a very long realtime transcript line \($0)." }
            .joined(separator: "\n")
        let line = CaptionLine(
            sourceText: text,
            translatedText: text,
            createdAt: Date(),
            isFinal: false
        )

        #expect(line.sourceText == text)
        #expect(line.translatedText == text)
        #expect(line.sourceDisplayText != text)
        #expect(line.translatedDisplayText != text)
        #expect(line.sourceDisplayText.hasPrefix("..."))
        #expect(line.translatedDisplayText.hasPrefix("..."))
    }

    @Test
    @MainActor
    func stopReplacesPendingTranslationPlaceholderOnVisibleLines() {
        let session = makeLocalTestSession()
        session.isRunning = true
        session.lines = [
            CaptionLine(
                sourceText: "But let's do the real test now.",
                translatedText: AppText.translating,
                createdAt: Date(),
                isFinal: false
            )
        ]

        session.stop()

        #expect(session.lines.first?.sourceText == "But let's do the real test now.")
        #expect(session.lines.first?.translatedText == AppText.translationCancelled)
        #expect(session.statusMessage == AppText.stopped)
    }

    @Test
    func liveSourceCompatibilityAcceptsGrowingTranscriptLine() {
        let requested = "This is a short local translation test."
        let current = "This is a short local translation test. The app should show Korean text quickly."

        #expect(TranslationSessionStore.isCompatibleLiveSource(current: current, requested: requested))
        #expect(TranslationSessionStore.isCompatibleLiveSource(current: "  \(current)", requested: requested))
        #expect(!TranslationSessionStore.isCompatibleLiveSource(current: "A different line.", requested: requested))
    }

    @Test
    func startReadinessBlocksAppleStartWhenAssetsAreStillChecking() {
        let readiness = StartReadinessPolicy.assess(
            requiredLocalModelAvailability: ModelAvailability(
                state: .checking,
                detail: "Checking"
            )
        )

        #expect(readiness.issue == .localAssetsChecking)
        #expect(!readiness.canStart)
    }

    @Test
    func startReadinessBlocksAppleStartWhenAssetsNeedDownload() {
        let readiness = StartReadinessPolicy.assess(
            requiredLocalModelAvailability: ModelAvailability(
                state: .downloadRequired,
                detail: "Download needed"
            )
        )

        #expect(readiness.issue == .localAssetsDownloadRequired)
        #expect(!readiness.canStart)
    }
}
