import Foundation
import ScreenCaptureKit
import Testing
@testable import AirTranslate

@Suite
struct AppleLifecycleP2Tests {
    @Test
    func userStoppedIsNormalWhileRealStreamFailureRemainsFatalAcrossRestart() {
        let userStopped = NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.Code.userStopped.rawValue
        )
        let systemFailure = NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.Code.internalError.rawValue
        )

        #expect(
            SystemAudioCapture.isUserStoppedError(
                SystemAudioCaptureLifecycleOutcome.userStopped
            )
        )
        #expect(!SystemAudioCapture.isFatalStopError(userStopped))
        #expect(SystemAudioCapture.isFatalStopError(systemFailure))

        var lifecycle = PipelineLifecycleState()
        let configuration = makeConfiguration()
        let firstGeneration = lifecycle.beginStart(configuration: configuration)
        #expect(
            lifecycle.markRunning(
                generation: firstGeneration,
                currentConfiguration: configuration
            ) == .valid
        )

        // A user stop does not enter the fatal pipeline-error path. The UI can
        // perform its normal stop and start a fresh capture generation.
        #expect(lifecycle.acceptsSample(generation: firstGeneration))
        lifecycle.stop()
        let secondGeneration = lifecycle.beginStart(configuration: configuration)
        #expect(
            lifecycle.markRunning(
                generation: secondGeneration,
                currentConfiguration: configuration
            ) == .valid
        )
        #expect(lifecycle.acceptsSample(generation: secondGeneration))

        let didFailSecondGeneration = lifecycle.fail(generation: secondGeneration)
        #expect(didFailSecondGeneration)
        #expect(lifecycle.phase == .stopped)
    }

    @Test
    @MainActor
    func externalUserStopKeepsVisibleTextUnlocksRestartsAndIgnoresStaleGeneration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirTranslateUserStopTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = makeLocalTestSession()
        let capture = session.systemAudioCaptureForTesting
        let firstPipeline = session.activateLiveCallbackPipelineForTesting()
        let firstGeneration = firstPipeline.generation
        session.liveSpeechTranscriber(
            firstPipeline.transcriber,
            didRecognize: "External user stop must retain visible captions.",
            language: .english,
            confidence: 0.9
        )
        #expect(await waitUntil {
            session.lines.last?.sourceText == "External user stop must retain visible captions."
        })

        #expect(
            SidebarSessionConfigurationAccess.isLocked(
                isRunning: session.isRunning,
                isStarting: session.isStarting
            )
        )

        session.systemAudioCaptureDidStopByUser(
            capture,
            generation: firstGeneration
        )
        await waitForStoppedPipeline(on: session)

        #expect(session.statusMessage == AppText.stopped)
        #expect(session.lines.last?.sourceText == "External user stop must retain visible captions.")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        #expect(
            !SidebarSessionConfigurationAccess.isLocked(
                isRunning: session.isRunning,
                isStarting: session.isStarting
            )
        )

        let secondGeneration = session.activateLiveCallbackPipelineForTesting().generation
        #expect(secondGeneration != firstGeneration)
        #expect(session.isRunning)
        #expect(
            SidebarSessionConfigurationAccess.isLocked(
                isRunning: session.isRunning,
                isStarting: session.isStarting
            )
        )

        session.systemAudioCaptureDidStopByUser(
            capture,
            generation: firstGeneration
        )
        await settleMainActorTasks()

        #expect(session.isRunning)
        #expect(
            SidebarSessionConfigurationAccess.isLocked(
                isRunning: session.isRunning,
                isStarting: session.isStarting
            )
        )

        session.systemAudioCaptureDidStopByUser(
            capture,
            generation: secondGeneration
        )
        await waitForStoppedPipeline(on: session)
    }

    @Test
    @MainActor
    func userStoppedThrownDuringInitialCaptureStartIsNormalNotStartFailure() async throws {
        let session = makeLocalTestSession()
        session.audioInputSource = .systemAudio
        let userStopped = NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.Code.userStopped.rawValue
        )

        let generation = try #require(
            await session.simulateSystemAudioStartFailureForTesting(userStopped)
        )

        #expect(generation > 0)
        #expect(!session.isRunning)
        #expect(!session.isStarting)
        #expect(session.statusMessage == AppText.stopped)
        #expect(session.statusMessage != AppText.startFailed(userStopped.localizedDescription))

        let restartedGeneration = session.activateLiveCallbackPipelineForTesting().generation
        #expect(restartedGeneration != generation)
        #expect(session.isRunning)
        session.stop()

        let failedSession = makeLocalTestSession()
        failedSession.audioInputSource = .systemAudio
        let systemFailure = NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.Code.internalError.rawValue
        )
        _ = try #require(
            await failedSession.simulateSystemAudioStartFailureForTesting(systemFailure)
        )
        #expect(!failedSession.isRunning)
        #expect(!failedSession.isStarting)
        #expect(failedSession.statusMessage == AppText.startFailed(systemFailure.localizedDescription))
    }



    @Test
    @MainActor
    func activeAppleSpeechBackpressureProducesVisibleControlledStop() async {
        let session = makeLocalTestSession()
        let activePipeline = session.activateLiveCallbackPipelineForTesting()
        let error = LiveSpeechTranscriberError.audioInputBackpressure(bufferLimit: 32)

        session.liveSpeechTranscriber(activePipeline.transcriber, didFail: error)
        await waitForStoppedPipeline(on: session)

        #expect(!session.isRunning)
        #expect(!session.isStarting)
        #expect(session.statusMessage == error.localizedDescription)
    }

    private func makeConfiguration() -> StartConfiguration {
        StartConfiguration(
            audioInputSource: .systemAudio,
            microphoneDeviceUniqueID: nil,
            sourceLanguage: .english,
            targetLanguage: .korean
        )
    }





    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 0.5,
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

    @MainActor
    private func settleMainActorTasks() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    @MainActor
    private func waitForStoppedPipeline(on session: TranslationSessionStore) async {
        #expect(await waitUntil {
            !session.isRunning && !session.isStarting
        })
    }
}
