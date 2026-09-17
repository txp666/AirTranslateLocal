import Foundation
import Testing
@testable import AirTranslate

@Suite
struct LongSessionCaptionPresentationTests {
    @Test
    @MainActor
    func standardSessionCoalescesLargeTranscriptUpdatesAndKeepsLatestText() async throws {
        let (session, directory) = try makeTranscriptionSession()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transcriber = LiveSpeechTranscriber()
        let baseText = String(repeating: "long session transcript ", count: 180)

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: baseText,
            language: .english,
            confidence: 0.9
        )
        #expect(await waitUntil { session.lines.last?.sourceText == baseText.trimmingCharacters(in: .whitespaces) })

        let initialRevision = session.lines.last?.revision
        for index in 1...100 {
            session.liveSpeechTranscriber(
                transcriber,
                didRecognize: baseText + "latest \(index)",
                language: .english,
                confidence: 0.9
            )
        }

        try await Task.sleep(for: .milliseconds(80))
        #expect(session.lines.last?.revision == initialRevision)

        // This assertion verifies eventual coalescing. The separate 50k burst
        // test owns the MainActor latency budget, so allow parallel test work
        // enough time to schedule the latest coalesced delivery.
        #expect(await waitUntil(timeout: 2.0) {
            session.lines.last?.sourceText.hasSuffix("latest 100") == true
        })
        #expect(session.lines.last?.revision == initialRevision.map { $0 + 1 })
    }

    @Test
    @MainActor
    func standardSessionStillPresentsShortTranscriptImmediately() async throws {
        let (session, directory) = try makeTranscriptionSession()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transcriber = LiveSpeechTranscriber()

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: "short transcript",
            language: .english,
            confidence: 0.9
        )
        #expect(await waitUntil { session.lines.last?.sourceText == "short transcript" })

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: "short transcript updated",
            language: .english,
            confidence: 0.9
        )

        #expect(await waitUntil(timeout: 0.1) {
            session.lines.last?.sourceText == "short transcript updated"
        })
    }

    @Test
    @MainActor
    func stopFlushesLatestCoalescedLongTranscript() async throws {
        let (session, directory) = try makeTranscriptionSession()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transcriber = LiveSpeechTranscriber()
        let baseText = String(repeating: "long stop transcript ", count: 200)

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: baseText,
            language: .english,
            confidence: 0.9
        )
        #expect(await waitUntil { session.lines.last != nil })

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: baseText + "final buffered words",
            language: .english,
            confidence: 0.9
        )
        await Task.yield()
        session.stop()

        #expect(session.lines.last?.sourceText.hasSuffix("final buffered words") == true)
        #expect(session.statusMessage == AppText.stopped)
    }

    @Test
    @MainActor
    func pauseFlushesLatestCoalescedLongTranscript() async throws {
        let (session, directory) = try makeTranscriptionSession()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transcriber = LiveSpeechTranscriber()
        let baseText = String(repeating: "long pause transcript ", count: 200)

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: baseText,
            language: .english,
            confidence: 0.9
        )
        #expect(await waitUntil { session.lines.last != nil })

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: baseText + "pause buffered words",
            language: .english,
            confidence: 0.9
        )
        await Task.yield()
        session.pause()

        #expect(session.lines.last?.sourceText.hasSuffix("pause buffered words") == true)
        #expect(session.isPaused)
    }

    @Test
    @MainActor
    func terminationFlushesLatestCoalescedLongTranscriptWithoutSaving() async throws {
        let (session, directory) = try makeTranscriptionSession()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transcriber = LiveSpeechTranscriber()
        let baseText = String(repeating: "long termination transcript ", count: 180)

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: baseText,
            language: .english,
            confidence: 0.9
        )
        #expect(await waitUntil { session.lines.last != nil })

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: baseText + "termination buffered words",
            language: .english,
            confidence: 0.9
        )
        await Task.yield()
        session.prepareForTermination()

        #expect(session.lines.last?.sourceText.hasSuffix("termination buffered words") == true)
        let savedFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(savedFiles.isEmpty)
    }



    @Test
    @MainActor
    func fiftyThousandCharacterBurstDoesNotStarveMainActorHeartbeat() async throws {
        let (session, directory) = try makeTranscriptionSession()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transcriber = LiveSpeechTranscriber()
        let baseText = String(repeating: "responsive long transcript ", count: 2_000)

        session.liveSpeechTranscriber(
            transcriber,
            didRecognize: baseText,
            language: .english,
            confidence: 0.9
        )
        #expect(await waitUntil(timeout: 0.6) { session.lines.last != nil })

        for index in 1...200 {
            session.liveSpeechTranscriber(
                transcriber,
                didRecognize: baseText + "latest \(index)",
                language: .english,
                confidence: 0.9
            )
        }

        let heartbeatScheduledAt = Date()
        let heartbeat = Task { @MainActor in Date() }
        let heartbeatDate = await heartbeat.value
        let heartbeatDelay = heartbeatDate.timeIntervalSince(heartbeatScheduledAt)

        #expect(heartbeatDelay < 0.5)
        session.stop()
        #expect(session.lines.last?.sourceText.hasSuffix("latest 200") == true)
    }

    @MainActor
    private func makeTranscriptionSession() throws -> (TranslationSessionStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirTranslateLongSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = makeLocalTestSession()
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.paragraphBreakSilenceInterval = 30
        session.isRunning = true
        return (session, directory)
    }



    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 0.3,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
