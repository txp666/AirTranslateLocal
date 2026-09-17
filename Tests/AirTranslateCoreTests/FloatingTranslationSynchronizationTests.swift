import Foundation
import Testing
@testable import AirTranslate

@Suite
@MainActor
struct FloatingTranslationSynchronizationTests {
    @Test
    func acceptedTranslationExtensionsAndRevisionsAppearImmediately() async throws {
        let (session, transcriber) = makeLiveSession()
        try await recognize("Hello everyone.", in: session, using: transcriber)
        let line = try #require(session.lines.last)

        // Each replacement represents the translation already accepted by the
        // main pane, including a correction that replaces an earlier prefix.
        for translation in ["안녕하세요", "안녕하세요 여러분", "반갑습니다 여러분"] {
            session.lines = [caption(
                replacing: line,
                source: "Hello everyone.",
                translation: translation,
                translatedSource: "Hello everyone."
            )]

            for mode in [FloatingCaptionDisplayMode.translation, .originalAndTranslation] {
                session.floatingCaptionDisplayMode = mode
                #expect(session.floatingCaptionDisplayMode == mode)
                #expect(session.floatingTranslationText == translation)
                #expect(session.floatingTranslationText == session.lines.last?.translatedText)
            }
        }
    }

    @Test
    func bilingualCaptionsKeepTheSourceSnapshotOfTheAcceptedTranslation() async throws {
        let (session, transcriber) = makeLiveSession()
        try await recognize("Meeting at nine.", in: session, using: transcriber)
        let line = try #require(session.lines.last)

        // Recognition has moved ahead and corrected the time, while the latest
        // accepted translation still belongs to the earlier source snapshot.
        session.lines = [caption(
            replacing: line,
            source: "Meeting at ten tomorrow.",
            translation: "회의는 아홉 시입니다.",
            translatedSource: "Meeting at nine."
        )]
        #expect(session.floatingTranslationText == "회의는 아홉 시입니다.")
        session.floatingCaptionDisplayMode = .originalAndTranslation

        #expect(session.floatingTranslationText == "회의는 아홉 시입니다.")
        #expect(session.floatingSourceText == "Meeting at nine.")

        // Once that correction is accepted, both halves switch to its snapshot
        // even though the original-only presentation may still be dwelling.
        session.lines = [caption(
            replacing: line,
            source: "Meeting at ten tomorrow.",
            translation: "회의는 열 시입니다.",
            translatedSource: "Meeting at ten."
        )]

        #expect(session.floatingTranslationText == "회의는 열 시입니다.")
        #expect(session.floatingSourceText == "Meeting at ten.")
    }

    @Test
    func bilingualCaptionsFallBackToTheAcceptedLineWhenNoSourceSnapshotExists() async throws {
        let (session, transcriber) = makeLiveSession()
        try await recognize("Old recognized wording.", in: session, using: transcriber)
        let line = try #require(session.lines.last)
        session.lines = [caption(
            replacing: line,
            source: "Corrected main-pane wording.",
            translation: "수정된 번역입니다.",
            translatedSource: ""
        )]
        session.floatingCaptionDisplayMode = .originalAndTranslation

        #expect(session.floatingSourceText == "Corrected main-pane wording.")
        #expect(session.floatingTranslationText == "수정된 번역입니다.")
    }

    @Test
    func placeholdersEmptyTranslationsAndClearedLinesDoNotRetainAnOldTranslation() async throws {
        let (session, transcriber) = makeLiveSession()
        try await recognize("The previous sentence.", in: session, using: transcriber)
        let acceptedLine = try #require(session.lines.last)
        session.acceptTranslationForTesting("이전 문장입니다.", for: acceptedLine, sourceText: "The previous sentence.")
        try #require(await eventually {
            session.lines.last?.translatedText == "이전 문장입니다."
        })
        #expect(session.floatingTranslationText == "이전 문장입니다.")
        let line = try #require(session.lines.last)

        for translation in [AppText.translating, "", " \n "] {
            session.lines = [caption(
                replacing: line,
                source: "The next sentence.",
                translation: translation,
                translatedSource: ""
            )]
            #expect(session.floatingTranslationText.isEmpty)
        }

        session.lines.removeAll()
        #expect(session.floatingTranslationText.isEmpty)
    }

    @Test
    func acceptedFormattingReplacesTheEarlierRawTranslation() async throws {
        let (session, transcriber) = makeLiveSession()
        try await recognize("The meeting is starting.", in: session, using: transcriber)
        let acceptedLine = try #require(session.lines.last)
        session.acceptTranslationForTesting("회의가 시작됩니다 시작됩니다", for: acceptedLine, sourceText: "The meeting is starting.")
        try #require(await eventually {
            session.lines.last?.translatedText == "회의가 시작됩니다\n시작됩니다"
        })
        let line = try #require(session.lines.last)

        // Simulate the canonical, cleaned translation accepted by the main
        // pane after the floating presentation has received the raw wording.
        session.lines = [caption(
            replacing: line,
            source: line.sourceText,
            translation: "회의가 시작됩니다.",
            translatedSource: line.translatedSourceText
        )]

        #expect(session.floatingTranslationText == "회의가 시작됩니다.")
    }

    @Test
    func longAcceptedTranslationsShowTheirLatestConfiguredLines() async throws {
        let (session, transcriber) = makeLiveSession()
        try await recognize("A long translated passage.", in: session, using: transcriber)
        let line = try #require(session.lines.last)
        session.lines = [caption(
            replacing: line,
            source: line.sourceText,
            translation: "첫 번째 문장.\n두 번째 문장.\n세 번째 문장.\n네 번째 문장.",
            translatedSource: line.sourceText
        )]
        session.floatingCaptionLineCount = .two

        #expect(session.floatingTranslationText == "세 번째 문장.\n네 번째 문장.")

        session.floatingCaptionLineCount = .three
        #expect(session.floatingTranslationText == "두 번째 문장.\n세 번째 문장.\n네 번째 문장.")
    }

    private func makeLiveSession() -> (TranslationSessionStore, LiveSpeechTranscriber) {
        let session = makeLocalTestSession()
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.paragraphBreakSilenceInterval = 30
        session.floatingCaptionDisplayMode = .translation
        session.floatingCaptionTextSize = .medium
        session.floatingCaptionLineCount = .three
        let pipeline = session.activateLiveCallbackPipelineForTesting()
        return (session, pipeline.transcriber)
    }

    private func recognize(
        _ source: String,
        in session: TranslationSessionStore,
        using transcriber: LiveSpeechTranscriber
    ) async throws {
        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: source,
            language: .english,
            confidence: 0.9
        )
        try #require(await eventually {
            session.lines.last?.sourceText == source && !session.floatingSourceText.isEmpty
        })
    }

    private func caption(
        replacing line: CaptionLine,
        source: String,
        translation: String,
        translatedSource: String
    ) -> CaptionLine {
        CaptionLine(
            id: line.id,
            sourceText: source,
            translatedText: translation,
            translatedSourceText: translatedSource,
            createdAt: line.createdAt,
            isFinal: false,
            revision: line.revision + 1
        )
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
