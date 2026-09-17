import Foundation
import Testing
@testable import AirTranslate

@MainActor
private final class ControlledLocalTranslator {
    private(set) var sources: [String] = []
    private var continuations: [CheckedContinuation<String, Error>?] = []

    func translate(_ source: String) async throws -> String {
        sources.append(source)
        return try await withCheckedThrowingContinuation { continuations.append($0) }
    }

    func finish(_ index: Int, with result: Result<String, Error>) {
        guard continuations.indices.contains(index), let continuation = continuations[index] else { return }
        continuations[index] = nil
        continuation.resume(with: result)
    }
}

private enum LocalPipelineTestError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Local model disconnected." }
}

@Suite
@MainActor
struct LocalTranslationPipelineTests {
    @Test
    func segmentedProgressPairsTranslationWithOnlyItsCompletedSourcePrefix() async throws {
        let translator = ControlledLocalTranslator()
        let session = makeSession(translator)
        let pipeline = session.activateLiveCallbackPipelineForTesting()
        session.floatingCaptionDisplayMode = .originalAndTranslation
        let firstParagraph = "The morning train leaves."
        let secondParagraph = "The evening train returns."
        let source = firstParagraph + "\n\n" + secondParagraph
        recognize(source, session: session, transcriber: pipeline.transcriber)
        try #require(await eventually { translator.sources.count == 1 })
        #expect(translator.sources[0] == firstParagraph)

        translator.finish(0, with: .success("아침 기차가 출발합니다."))
        try #require(await eventually { translator.sources.count == 2 })
        #expect(translator.sources[1] == secondParagraph)
        #expect(session.lines.last?.sourceText == source)
        #expect(session.lines.last?.translatedSourceText == firstParagraph)
        #expect(session.floatingSourceText == firstParagraph)
        #expect(session.floatingTranslationText == "아침 기차가 출발합니다.")

        translator.finish(1, with: .success("저녁 기차가 돌아옵니다."))
        try #require(await eventually { session.lines.last?.translatedSourceText == source })
        #expect(session.lines.last?.translatedText.contains("아침 기차가 출발합니다.") == true)
        #expect(session.lines.last?.translatedText.contains("저녁 기차가 돌아옵니다.") == true)
        #expect(session.floatingSourceText.contains(secondParagraph))
        session.stop()
    }

    @Test
    func acceptedLocalTranslationUpdatesBothDisplaysWithMatchingSourceSnapshot() async throws {
        let translator = ControlledLocalTranslator()
        let session = makeSession(translator)
        let pipeline = session.activateLiveCallbackPipelineForTesting()
        session.floatingCaptionDisplayMode = .originalAndTranslation
        recognize("Meeting at nine.", session: session, transcriber: pipeline.transcriber)
        try #require(await eventually { translator.sources.count == 1 })

        recognize("Meeting at nine. Tomorrow morning.", session: session, transcriber: pipeline.transcriber)
        try #require(await eventually { session.lines.last?.sourceText.contains("Tomorrow") == true })
        translator.finish(0, with: .success("회의는 아홉 시입니다."))
        try #require(await eventually { session.lines.last?.translatedText == "회의는 아홉 시입니다." })
        #expect(session.floatingTranslationText == session.lines.last?.translatedText)
        #expect(session.floatingSourceText == "Meeting at nine.")
        try #require(await eventually { translator.sources.count == 2 })
        translator.finish(1, with: .success("회의는 내일 아침 아홉 시입니다."))
        try #require(await eventually { session.lines.last?.translatedText == "회의는 내일 아침 아홉 시입니다." })
        #expect(session.lines.last?.translatedSourceText == "Meeting at nine. Tomorrow morning.")
        #expect(session.floatingSourceText == "Meeting at nine.\nTomorrow morning.")
        #expect(session.floatingTranslationText == session.lines.last?.translatedText)
        session.stop()
    }

    @Test
    func localFailurePreservesPreviouslyAcceptedTranslation() async throws {
        let translator = ControlledLocalTranslator()
        let session = makeSession(translator)
        let pipeline = session.activateLiveCallbackPipelineForTesting()
        recognize("Hello everyone.", session: session, transcriber: pipeline.transcriber)
        try #require(await eventually { translator.sources.count == 1 })
        translator.finish(0, with: .success("안녕하세요 여러분."))
        try #require(await eventually { session.lines.last?.translatedText == "안녕하세요\n여러분." })

        recognize("Hello everyone. The meeting starts now.", session: session, transcriber: pipeline.transcriber)
        try #require(await eventually { translator.sources.count == 2 })
        translator.finish(1, with: .failure(LocalPipelineTestError.unavailable))
        try #require(await eventually { session.statusMessage == "Local model disconnected." })
        #expect(session.lines.last?.translatedText == "안녕하세요\n여러분.")
        #expect(session.floatingTranslationText == "안녕하세요\n여러분.")
        session.stop()
    }

    @Test(arguments: [false, true])
    func stoppedGenerationCannotOverwriteRestartedTranslationOrStatus(oldFails: Bool) async throws {
        let translator = ControlledLocalTranslator()
        let session = makeSession(translator)
        let first = session.activateLiveCallbackPipelineForTesting()
        recognize("Old session.", session: session, transcriber: first.transcriber)
        try #require(await eventually { translator.sources.count == 1 })
        session.stop()

        let second = session.activateLiveCallbackPipelineForTesting()
        recognize("New session.", session: session, transcriber: second.transcriber)
        try #require(await eventually { translator.sources.count == 2 })
        translator.finish(1, with: .success("새 세션입니다."))
        try #require(await eventually { session.lines.last?.translatedText == "새 세션입니다." })
        let status = session.statusMessage
        translator.finish(0, with: oldFails ? .failure(LocalPipelineTestError.unavailable) : .success("이전 세션입니다."))
        for _ in 0..<20 { await Task.yield() }
        #expect(session.isRunning)
        #expect(session.lines.last?.sourceText == "New session.")
        #expect(session.lines.last?.translatedText == "새 세션입니다.")
        #expect(session.floatingTranslationText == "새 세션입니다.")
        #expect(session.statusMessage == status)
        session.stop()
    }

    @Test
    func pauseRejectsNewRecognitionButAcceptsPendingTranslationAndResumeContinues() async throws {
        let translator = ControlledLocalTranslator()
        let session = makeSession(translator)
        let pipeline = session.activateLiveCallbackPipelineForTesting()
        recognize("Hello everyone.", session: session, transcriber: pipeline.transcriber)
        try #require(await eventually { translator.sources.count == 1 })
        session.pause()
        #expect(session.isPaused)
        recognize("Unwanted audio while paused.", session: session, transcriber: pipeline.transcriber)
        translator.finish(0, with: .success("안녕하세요 여러분."))
        try #require(await eventually { session.lines.last?.translatedText == "안녕하세요\n여러분." })
        #expect(session.lines.last?.sourceText == "Hello everyone.")
        #expect(session.statusMessage == AppText.paused)
        session.resume()
        #expect(!session.isPaused)
        recognize("Hello everyone. We can continue.", session: session, transcriber: pipeline.transcriber)
        try #require(await eventually { session.lines.last?.sourceText.contains("We can continue") == true })
        session.stop()
        // Stop may precede the next debounced request; no real service is contacted.
        for index in 1..<translator.sources.count { translator.finish(index, with: .failure(CancellationError())) }
    }

    private func makeSession(_ translator: ControlledLocalTranslator) -> TranslationSessionStore {
        let session = TranslationSessionStore(
            preferences: InMemoryUserDefaults(),
            speechAvailabilityProvider: { _ in ModelAvailability(state: .installed, detail: "Installed") },
            translationProvider: { text, _, _, _ in try await translator.translate(text) }
        )
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.paragraphBreakSilenceInterval = 30
        session.floatingCaptionLineCount = .three
        return session
    }

    private func recognize(_ source: String, session: TranslationSessionStore, transcriber: LiveSpeechTranscriber) {
        session.liveSpeechTranscriber(transcriber, didRecognize: source, language: .english, confidence: 0.9)
    }

    private func eventually(_ predicate: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }
}
