import AVFAudio
import AppKit
import AirTranslateCore
import Foundation
import Observation

enum PrivacySettingsPane {
    case screenRecording
    case systemAudioRecording
    case microphone
    case speechRecognition

    fileprivate var anchor: String {
        switch self {
        case .screenRecording, .systemAudioRecording:
            // macOS groups Screen Recording and System Audio Recording in this pane.
            "Privacy_ScreenCapture"
        case .microphone:
            "Privacy_Microphone"
        case .speechRecognition:
            "Privacy_SpeechRecognition"
        }
    }
}

private enum SettingsKey {
    static let sourceLanguageID = "sourceLanguageID"
    static let targetLanguageID = "targetLanguageID"
    static let localTranslationBaseURLString = "localTranslationBaseURLString"
    static let localTranslationModelID = "localTranslationModelID"
    static let floatingCaptionDisplayMode = "floatingCaptionDisplayMode"
    static let floatingCaptionTextSize = "floatingCaptionTextSize"
    static let floatingCaptionLineCount = "floatingCaptionLineCount"
    static let showsFloatingCaptionBackground = "showsFloatingCaptionBackground"
    static let keepsFloatingCaptionAboveOtherWindows = "keepsFloatingCaptionAboveOtherWindows"
    static let audioInputSource = "audioInputSource"
    static let selectedMicrophoneInputDeviceID = "selectedMicrophoneInputDeviceID"
}

private struct TranslationRequest {
    let line: CaptionLine
    let sourceText: String
    let translationSourceText: String
    let source: LanguageOption
    let target: LanguageOption
}

private struct PendingCaptionPresentation {
    let lineID: UUID
    let sourceText: String
    let isFinal: Bool
    let source: LanguageOption
    let target: LanguageOption
}

private struct PendingRecognizedCaption {
    let sourceText: String
    let recognizedLanguage: LanguageOption
    let confidence: Double
}

struct StartConfiguration: Equatable {
    let audioInputSource: AudioInputSource
    let microphoneDeviceUniqueID: String?
    let sourceLanguage: LanguageOption
    let targetLanguage: LanguageOption
    var localTranslationBaseURLString = LocalTranslationConfiguration.defaultBaseURLString
    var localTranslationModelID = LocalTranslationConfiguration.defaultModelID
    var sampleRate: Int { 16_000 }
    var localTranslationConfiguration: LocalTranslationConfiguration {
        LocalTranslationConfiguration(baseURLString: localTranslationBaseURLString, modelID: localTranslationModelID)
    }
}

enum PipelineLifecyclePhase: Equatable {
    case stopped
    case starting
    case running
}

enum PipelineStartValidation: Equatable {
    case valid
    case staleGeneration
    case configurationChanged
}

struct PipelineLifecycleState {
    private(set) var generation: UInt64 = 0
    private(set) var phase = PipelineLifecyclePhase.stopped
    private(set) var startConfiguration: StartConfiguration?

    mutating func beginStart(configuration: StartConfiguration) -> UInt64 {
        generation &+= 1
        phase = .starting
        startConfiguration = configuration
        return generation
    }

    mutating func validateStart(
        generation expectedGeneration: UInt64,
        currentConfiguration: StartConfiguration
    ) -> PipelineStartValidation {
        guard generation == expectedGeneration, phase == .starting else {
            return .staleGeneration
        }
        guard startConfiguration == currentConfiguration else {
            generation &+= 1
            phase = .stopped
            startConfiguration = nil
            return .configurationChanged
        }
        return .valid
    }

    mutating func markRunning(
        generation expectedGeneration: UInt64,
        currentConfiguration: StartConfiguration
    ) -> PipelineStartValidation {
        let validation = validateStart(
            generation: expectedGeneration,
            currentConfiguration: currentConfiguration
        )
        if validation == .valid {
            phase = .running
        }
        return validation
    }

    mutating func fail(generation expectedGeneration: UInt64) -> Bool {
        guard generation == expectedGeneration, phase != .stopped else {
            return false
        }
        stop()
        return true
    }

    mutating func failCurrent() -> Bool {
        guard phase != .stopped else { return false }
        stop()
        return true
    }

    mutating func stop() {
        generation &+= 1
        phase = .stopped
        startConfiguration = nil
    }

    func acceptsSample(generation expectedGeneration: UInt64) -> Bool {
        generation == expectedGeneration && phase == .running
    }

    func isActive(generation expectedGeneration: UInt64) -> Bool {
        generation == expectedGeneration && phase != .stopped
    }
}

private enum PipelineStartError: LocalizedError {
    case configurationChanged

    var errorDescription: String? {
        switch self {
        case .configurationChanged:
            AppText.localized(
                english: "Capture settings changed while starting. Start again.",
                korean: "시작하는 동안 캡처 설정이 변경되었습니다. 다시 시작해 주세요.",
                japanese: "開始中にキャプチャ設定が変更されました。もう一度開始してください。",
                chineseSimplified: "启动期间捕获设置已更改。请重新启动。"
            )
        }
    }
}

private final class AudioSamplePipelineRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var pipeline: (generation: UInt64, transcriber: LiveSpeechTranscriber)?

    func publish(generation: UInt64, transcriber: LiveSpeechTranscriber) {
        lock.lock()
        pipeline = (generation, transcriber)
        lock.unlock()
    }

    func clear() {
        lock.lock()
        pipeline = nil
        lock.unlock()
    }

    func append(_ sampleBuffer: CMSampleBuffer, generation: UInt64) {
        lock.lock()
        let current = pipeline
        lock.unlock()
        guard let current, current.generation == generation else { return }
        current.transcriber.append(sampleBuffer)
    }
}

@MainActor
@Observable
final class TranslationSessionStore {
    private static let maxTranslationCacheEntries = 2_000
    private static let largeTranscriptPresentationCharacterLimit = 4_000
    private static let largeTranscriptPresentationInterval: TimeInterval = 0.35
    private static let largeTranscriptRecognitionDeliveryInterval: TimeInterval = 0.25
    private static let translationCacheHitYieldInterval = 32
    private static let largeTranscriptTranslationCharacterLimit = 4_000
    private static let veryLargeTranscriptTranslationCharacterLimit = 10_000
    private static let floatingCaptionEarlyRevisionWindow = 0.45
    private static let minimumFloatingCaptionDwell = 1.6
    private static let maximumFloatingCaptionDwell = 2.8
    private static let floatingCaptionSilenceHideDelay: TimeInterval = 3.5

    var isRunning = false
    var isStarting = false
    var isPaused = false
    var statusMessage = AppText.ready
    var sourceLanguage = LanguageOption.english {
        didSet { sourceLanguageDidChange() }
    }
    var targetLanguage = LanguageOption.chineseSimplified {
        didSet { configurationDidChange() }
    }
    var audioInputSource = AudioInputSource.systemAudio {
        didSet { persistSelectedSettings() }
    }
    var selectedMicrophoneInputDeviceID = MicrophoneInputDevice.systemDefaultID {
        didSet { persistSelectedSettings() }
    }
    var microphoneInputDevices = MicrophoneDeviceCatalog.availableInputDevices()
    var localTranslationBaseURLString = LocalTranslationConfiguration.defaultBaseURLString {
        didSet { localConfigurationDidChange() }
    }
    var localTranslationModelID = LocalTranslationConfiguration.defaultModelID {
        didSet { localConfigurationDidChange() }
    }
    var localTranslationConnectionState = LocalTranslationConnectionState.unchecked
    var speechAvailability = ModelAvailability.checking
    var floatingCaptionDisplayMode = FloatingCaptionDisplayMode.translation {
        didSet { persistSelectedSettings() }
    }
    var floatingCaptionTextSize = FloatingCaptionTextSize.medium {
        didSet { persistSelectedSettings() }
    }
    var floatingCaptionLineCount = FloatingCaptionLineCount.three {
        didSet { persistSelectedSettings() }
    }
    var showsFloatingCaptionBackground = false {
        didSet { persistSelectedSettings() }
    }
    var keepsFloatingCaptionAboveOtherWindows = true {
        didSet { persistSelectedSettings() }
    }
    private(set) var isFloatingCaptionHiddenAfterSilence = false
    private(set) var latestAudioLevel: Float?
    var lines: [CaptionLine] = []
    // A fixed pause threshold keeps operation simple while preserving paragraph boundaries.
    var paragraphBreakSilenceInterval = 5.0

    private let systemAudioCapture = SystemAudioCapture()
    private let microphoneAudioCapture = MicrophoneAudioCapture()
    @ObservationIgnored private var transcriber = LiveSpeechTranscriber()
    @ObservationIgnored nonisolated private let audioSamplePipelineRegistry = AudioSamplePipelineRegistry()
    private let preferences: UserDefaults
    private let localTranslator: LocalTranslationService
    private let localModelRuntime: LocalModelRuntimeManager
    private let speechAvailabilityProvider: (LanguageOption) async -> ModelAvailability
    private let speechAssetDownloader: (LanguageOption) async throws -> Void
    private let translationProvider: (@MainActor (String, LanguageOption, LanguageOption, LocalTranslationConfiguration) async throws -> String)?
    private var audioSampleCount = 0
    private var lastRecognizedText = ""
    private var lastRecognizedWasFinal = false
    private var lastRecognitionAt = Date.distantPast
    private var currentLineID: UUID?
    private var lastCaptionPresentationUpdateAt = Date.distantPast
    private var pendingCaptionPresentation: PendingCaptionPresentation?
    private var captionPresentationTask: Task<Void, Never>?
    private var pendingRecognizedCaption: PendingRecognizedCaption?
    private var recognizedCaptionDeliveryTask: Task<Void, Never>?
    private var lastRecognizedCaptionDeliveryAt = Date.distantPast
    private var isLargeTranscriptRecognitionCoalescingActive = false
    private var transcriptCleanupTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var translationTaskGeneration = 0
    private var latestTranslationRequest: TranslationRequest?
    private var translationBurstStartedAt = Date.distantPast
    private var committedSourceText = ""
    private var currentPartialText = ""
    private var currentPartialLanguage: LanguageOption?
    private var pendingParagraphBreakBeforePartial = false
    private var floatingCommittedSourceText = ""
    private var floatingCurrentPartialText = ""
    private var pendingFloatingParagraphBreakBeforePartial = false
    private var floatingPresentedSourceText = ""
    private var floatingQueuedSourceText = ""
    private var floatingPresentedAt = Date.distantPast
    private var floatingPresentedUnreadLength = 0
    private var floatingPresentationTask: Task<Void, Never>?
    private var floatingCaptionHideTask: Task<Void, Never>?
    private var sourceLanguageByLineID: [UUID: LanguageOption] = [:]
    private var pendingTranslationSourceText = ""
    private var translationSegmentCache = TranslationSegmentCache(capacity: TranslationSessionStore.maxTranslationCacheEntries)
    private var isRestoringSelectedSettings = false
    private var modelAvailabilityTask: Task<Void, Never>?
    private var speechDownloadTask: Task<Void, Never>?
    private var speechDownloadGeneration = UUID()
    private var localTranslationConnectionTask: Task<Void, Never>?
    private var localConnectionGeneration = UUID()
    private var localRuntimeGeneration = UUID()
    private var localPreparationTask: Task<Void, Never>?
    private var localPreparationGeneration = UUID()
    private var captureStartTask: Task<Void, Never>?
    private var activeCaptureStartGeneration: UInt64?
#if DEBUG
    private var permissionSuspendedStartContinuations: [UInt64: CheckedContinuation<Void, Never>] = [:]
#endif
    private var captureStopTask: Task<Void, Never>?
    private var pipelineLifecycle = PipelineLifecycleState()
    private var activeCaptionerGeneration: UInt64?

    private var usesLongSessionMode: Bool {
        (lines.last?.sourceText.utf16.count ?? 0) >= Self.largeTranscriptPresentationCharacterLimit
    }
    var shouldCoalesceTranscriptAutoScroll: Bool { isRunning || usesLongSessionMode }
    var localModelRuntimeState: LocalModelRuntimeState { localModelRuntime.state }
    var localModelRuntimeLog: String { localModelRuntime.logText }
    var canStartTranslation: Bool {
        !isRunning && !isStarting && localModelRuntimeState == .ready
            && localTranslationConnectionState == .available
            && speechAvailability.state == .installed
            && sourceLanguage != targetLanguage
    }
    var languageSummary: String { "\(sourceLanguage.localizedTitle) → \(targetLanguage.localizedTitle)" }
    var hasTranscriptContent: Bool { !lines.isEmpty }
    var shouldShowTranscript: Bool { isRunning || !lines.isEmpty }
    var shouldShowTranslationPane: Bool { true }
    var availableFloatingCaptionDisplayModes: [FloatingCaptionDisplayMode] { FloatingCaptionDisplayMode.allCases }

    init(
        preferences: UserDefaults = .standard,
        localTranslator: LocalTranslationService = LocalTranslationService(),
        speechAvailabilityProvider: @escaping (LanguageOption) async -> ModelAvailability = { language in
            await ModelAvailabilityChecker.speechAvailability(for: language)
        },
        speechAssetDownloader: @escaping (LanguageOption) async throws -> Void = { language in
            try await ModelAvailabilityChecker.downloadSpeechAssets(for: language)
        },
        translationProvider: (@MainActor (String, LanguageOption, LanguageOption, LocalTranslationConfiguration) async throws -> String)? = nil
    ) {
        self.preferences = preferences
        self.localTranslator = localTranslator
        self.localModelRuntime = LocalModelRuntimeManager(translator: localTranslator)
        self.speechAvailabilityProvider = speechAvailabilityProvider
        self.speechAssetDownloader = speechAssetDownloader
        self.translationProvider = translationProvider
        restoreSelectedSettings()
        systemAudioCapture.delegate = self
        microphoneAudioCapture.delegate = self
        transcriber.delegate = self
        refreshSpeechAvailability()
    }

    private func configurationDidChange() {
        guard !isRestoringSelectedSettings else { return }
        resetTranslationCache()
        persistSelectedSettings()
    }

    private func sourceLanguageDidChange() {
        guard !isRestoringSelectedSettings else { return }
        speechDownloadGeneration = UUID()
        speechDownloadTask?.cancel()
        speechDownloadTask = nil
        configurationDidChange()
        refreshSpeechAvailability()
    }

    private func invalidateLocalConnectionCheck() {
        localConnectionGeneration = UUID()
        localTranslationConnectionTask?.cancel()
        localTranslationConnectionTask = nil
    }

    private func localConfigurationDidChange() {
        guard !isRestoringSelectedSettings else { return }
        localRuntimeGeneration = UUID()
        invalidateLocalConnectionCheck()
        localTranslationConnectionState = .unchecked
        configurationDidChange()
    }

    func useQuickSourceLanguage(_ language: LanguageOption) {
        guard !isRunning, !isStarting else { return }
        sourceLanguage = language
        if targetLanguage == language {
            targetLanguage = language == .chineseSimplified ? .english : .chineseSimplified
        }
    }

    func useQuickTargetLanguage(_ language: LanguageOption) {
        guard !isRunning, !isStarting else { return }
        targetLanguage = language
        if sourceLanguage == language {
            sourceLanguage = language == .english ? .chineseSimplified : .english
        }
    }

    func swapQuickLanguagePair() {
        guard !isRunning, !isStarting else { return }
        let previousSource = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = previousSource
    }

    func prepareLocalModel() {
        guard !isRunning, !isStarting else { return }
        let configuration = localTranslationConfiguration
        let generation = UUID()
        localRuntimeGeneration = generation
        invalidateLocalConnectionCheck()
        localTranslationConnectionState = .checking
        statusMessage = AppText.localModelRuntimeStarting
        localModelRuntime.startIfNeeded(
            configuration: configuration,
            onReady: { [weak self] in
                guard let self, generation == self.localRuntimeGeneration,
                      configuration == self.localTranslationConfiguration else { return }
                self.localTranslationConnectionState = .available
                if !self.isRunning, !self.isStarting { self.statusMessage = AppText.localTranslationAvailable }
            },
            onFailure: { [weak self] message in
                guard let self, generation == self.localRuntimeGeneration,
                      configuration == self.localTranslationConfiguration else { return }
                self.localTranslationConnectionState = .unavailable(message)
                if self.isRunning || self.isStarting { self.handleFatalPipelineError(LocalRuntimeFailure(message: message)) }
                else { self.statusMessage = message }
            }
        )
    }

    func installLocalModel() {
        guard !isRunning, !isStarting, localPreparationTask == nil else { return }
        let configuration = localTranslationConfiguration
        let generation = UUID()
        localPreparationGeneration = generation
        localRuntimeGeneration = UUID()
        invalidateLocalConnectionCheck()
        localTranslationConnectionState = .checking
        localPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.localPreparationGeneration == generation { self.localPreparationTask = nil }
            }
            do {
                try await localModelRuntime.prepare(configuration: configuration, downloadModel: true)
                try Task.checkCancellation()
                guard generation == localPreparationGeneration,
                      configuration == localTranslationConfiguration else { return }
                prepareLocalModel()
            } catch is CancellationError {
                return
            } catch {
                guard generation == localPreparationGeneration else { return }
                localTranslationConnectionState = .unavailable(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
        }
    }

    func cancelLocalModelPreparation() {
        localRuntimeGeneration = UUID()
        invalidateLocalConnectionCheck()
        localPreparationGeneration = UUID()
        localPreparationTask?.cancel()
        localPreparationTask = nil
        localModelRuntime.cancelPreparation()
        localTranslationConnectionState = .unchecked
        if !isRunning, !isStarting { statusMessage = AppText.ready }
    }

    func refreshSpeechAvailability() {
        guard !isRestoringSelectedSettings else { return }
        let language = sourceLanguage
        modelAvailabilityTask?.cancel()
        speechAvailability = .checking
        modelAvailabilityTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let availability = await speechAvailabilityProvider(language)
            guard !Task.isCancelled, sourceLanguage == language else { return }
            speechAvailability = availability
            modelAvailabilityTask = nil
        }
    }

    func downloadSpeechAssets() {
        guard !isStarting, !isRunning, speechDownloadTask == nil, speechAvailability.state.canDownload else { return }
        let language = sourceLanguage
        let generation = UUID()
        speechDownloadGeneration = generation
        modelAvailabilityTask?.cancel()
        speechAvailability = ModelAvailability(state: .downloading, detail: AppText.modelStatusDownloading)
        speechDownloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.speechDownloadGeneration == generation { self.speechDownloadTask = nil }
            }
            do {
                try await speechAssetDownloader(language)
                try Task.checkCancellation()
                guard generation == speechDownloadGeneration, sourceLanguage == language else { return }
                refreshSpeechAvailability()
            } catch is CancellationError {} catch {
                guard !Task.isCancelled, generation == speechDownloadGeneration, sourceLanguage == language else { return }
                speechAvailability = ModelAvailability(state: .failed, detail: error.localizedDescription)
            }
        }
    }

    func startReadinessAssessment() -> StartReadinessAssessment {
        StartReadinessPolicy.assess(requiredLocalModelAvailability: speechAvailability)
    }

    private func statusMessage(for readiness: StartReadinessAssessment) -> String {
        switch readiness.issue {
        case nil: AppText.ready
        case .localAssetsChecking: AppText.startBlockedLocalAssetsChecking
        case .localAssetsDownloadRequired: AppText.startBlockedLocalAssetsDownloadRequired
        case .localAssetsUnavailable(let detail): AppText.startBlockedLocalAssetsUnavailable(detail)
        }
    }

    private func currentStartConfiguration() -> StartConfiguration {
        StartConfiguration(
            audioInputSource: audioInputSource,
            microphoneDeviceUniqueID: selectedMicrophoneDevice.uniqueID,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            localTranslationBaseURLString: localTranslationBaseURLString,
            localTranslationModelID: localTranslationModelID
        )
    }

    private func finishPipeline(statusOverride: String?) {
        invalidateCaptureStartAttempt()
        flushPendingRecognizedCaption()
        flushPendingCaptionPresentation()
        resetLiveSessionState(clearsVisibleLines: false)
        isPaused = false
        setCaptionersPaused(false)
        isStarting = false
        isRunning = false
        statusMessage = statusOverride ?? AppText.stopped
        stopCaptioners()
        let previousStopTask = captureStopTask
        captureStopTask = Task { @MainActor in
            if let previousStopTask { await previousStopTask.value }
            await stopCapture()
        }
    }

    func prepareForTermination() {
        pipelineLifecycle.stop()
        finishPipeline(statusOverride: nil)
        modelAvailabilityTask?.cancel()
        speechDownloadTask?.cancel()
        invalidateLocalConnectionCheck()
        localRuntimeGeneration = UUID()
        localPreparationGeneration = UUID()
        localPreparationTask?.cancel()
        localModelRuntime.stop()
        floatingCaptionHideTask?.cancel()
    }

    private func stopCaptioners() {
        audioSamplePipelineRegistry.clear()
        activeCaptionerGeneration = nil
        transcriber.delegate = nil
        transcriber.stop()
    }

    private func setCaptionersPaused(_ isPaused: Bool) { transcriber.setPaused(isPaused) }

    private var translationEngineCacheID: String {
        "local:\(localTranslationBaseURLString):\(localTranslationModelID)"
    }

    private func organizeTranscript(_ text: String, language: LanguageOption) -> String {
        TranscriptTextProcessor.organizeTranscript(text, languageID: language.id)
    }

    private func translationDirection(recognizedLanguage: LanguageOption) -> (source: LanguageOption, target: LanguageOption) {
        (sourceLanguage, targetLanguage)
    }

    private func translateSegment(_ text: String, source: LanguageOption, target: LanguageOption) async throws -> String {
        if let translationProvider {
            return try await translationProvider(text, source, target, localTranslationConfiguration)
        }
        return try await localTranslator.translate(text, source: source, target: target, configuration: localTranslationConfiguration)
    }

    func start() {
        guard !isRunning, !isStarting else { return }

        let readiness = startReadinessAssessment()
        guard readiness.canStart else {
            if readiness.issue == .localAssetsDownloadRequired { downloadSpeechAssets() }
            statusMessage = statusMessage(for: readiness)
            return
        }

        invalidateCaptureStartAttempt()
        let configuration = currentStartConfiguration()
        let generation = pipelineLifecycle.beginStart(configuration: configuration)
        activeCaptureStartGeneration = generation
        isPaused = false
        setCaptionersPaused(false)
        isStarting = true
        statusMessage = configuration.audioInputSource == .microphone
            ? AppText.checkingMicrophonePermission
            : AppText.checkingScreenPermission

        captureStartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.completeCaptureStartAttempt(generation: generation) }
            do {
                if let captureStopTask {
                    await captureStopTask.value
                    try validatePipelineStart(generation: generation, configuration: configuration)
                    self.captureStopTask = nil
                }
                try validatePipelineStart(generation: generation, configuration: configuration)
                do {
                    invalidateLocalConnectionCheck()
                    localTranslationConnectionState = .checking
                    statusMessage = AppText.localTranslationChecking
                    do {
                        try await localTranslator.checkConnection(
                            configuration: configuration.localTranslationConfiguration
                        )
                        try validatePipelineStart(generation: generation, configuration: configuration)
                        localTranslationConnectionState = .available
                    } catch {
                        try validatePipelineStart(generation: generation, configuration: configuration)
                        localTranslationConnectionState = .unavailable(error.localizedDescription)
                        throw error
                    }
                }
                if configuration.audioInputSource == .systemAudio {
                    try systemAudioCapture.requestScreenRecordingAccess()
                }
                try validatePipelineStart(generation: generation, configuration: configuration)
                statusMessage = AppText.checkingSpeechPermission
                try await startAppleSpeechTranscriber(configuration: configuration, generation: generation)
                try validatePipelineStart(generation: generation, configuration: configuration)
                audioSamplePipelineRegistry.publish(
                    generation: generation,
                    transcriber: transcriber
                )

                statusMessage = AppText.startingCapture(for: configuration.audioInputSource)
                switch configuration.audioInputSource {
                case .systemAudio:
                    try await systemAudioCapture.start(
                        sampleRate: configuration.sampleRate,
                        generation: generation
                    )
                case .microphone:
                    try await microphoneAudioCapture.start(
                        sampleRate: configuration.sampleRate,
                        deviceUniqueID: configuration.microphoneDeviceUniqueID,
                        generation: generation
                    )
                }
                try validatePipelineStart(generation: generation, configuration: configuration)
                let promotion = pipelineLifecycle.markRunning(
                    generation: generation,
                    currentConfiguration: currentStartConfiguration()
                )
                switch promotion {
                case .valid:
                    break
                case .configurationChanged:
                    throw PipelineStartError.configurationChanged
                case .staleGeneration:
                    throw CancellationError()
                }
                resetLiveSessionState(clearsVisibleLines: true)
                isRunning = true
                isStarting = false
                statusMessage = AppText.listeningForSpeech(from: configuration.audioInputSource)
            } catch let error as CancellationError {
                await handleCancelledCaptureStart(
                    generation: generation,
                    error: error
                )
            } catch let error as PipelineStartError {
                await handlePipelineStartError(
                    error,
                    generation: generation
                )
            } catch {
                await handleCaptureStartFailure(
                    error,
                    generation: generation,
                    configuration: configuration
                )
            }
        }
    }

    func stop() {
        guard isRunning || isStarting else { return }
        let shouldRefreshConnection = isStarting && localTranslationConnectionState == .checking
        pipelineLifecycle.stop()
        finishPipeline(statusOverride: nil)
        // Cancelling the capture start also cancels its connection check. A
        // separate generation-owned probe restores Start without reviving the
        // cancelled capture or leaving the UI stuck in "Checking".
        if shouldRefreshConnection {
            refreshLocalTranslationConnection(updatesStatusMessage: false)
        }
    }

    private func invalidateCaptureStartAttempt() {
        activeCaptureStartGeneration = nil
        captureStartTask?.cancel()
        captureStartTask = nil
    }

    private func completeCaptureStartAttempt(generation: UInt64) {
        guard activeCaptureStartGeneration == generation else { return }
        activeCaptureStartGeneration = nil
        captureStartTask = nil
        if !isRunning {
            isStarting = false
        }
    }

    private func handleCancelledCaptureStart(
        generation: UInt64,
        error: Error
    ) async {
        guard pipelineLifecycle.fail(generation: generation) else {
            // stop() may have invalidated this task while a permission prompt
            // was suspended. It must not affect a newer generation, but it can
            // still have resumed and initialized the old captioners.
            stopCaptionersIfOwned(by: generation)
            return
        }

        finishPipeline(statusOverride: AppText.startFailed(error.localizedDescription))
    }

    private func handlePipelineStartError(
        _ error: PipelineStartError,
        generation: UInt64
    ) async {
        if pipelineLifecycle.isActive(generation: generation) {
            _ = pipelineLifecycle.fail(generation: generation)
        }
        guard activeCaptureStartGeneration == generation else {
            stopCaptionersIfOwned(by: generation)
            return
        }

        finishPipeline(statusOverride: AppText.startFailed(error.localizedDescription))
    }

    private func stopCaptionersIfOwned(by generation: UInt64) {
        guard activeCaptionerGeneration == generation else { return }
        stopCaptioners()
    }

    private func validatePipelineStart(
        generation: UInt64,
        configuration: StartConfiguration
    ) throws {
        guard !Task.isCancelled, isStarting else {
            throw CancellationError()
        }

        switch pipelineLifecycle.validateStart(
            generation: generation,
            currentConfiguration: currentStartConfiguration()
        ) {
        case .valid:
            guard configuration == currentStartConfiguration() else {
                throw PipelineStartError.configurationChanged
            }
        case .staleGeneration:
            throw CancellationError()
        case .configurationChanged:
            throw PipelineStartError.configurationChanged
        }
    }

    private func handleFatalPipelineError(
        _ error: Error,
        generation: UInt64? = nil
    ) {
        let didEndLifecycle: Bool
        if let generation {
            didEndLifecycle = pipelineLifecycle.fail(generation: generation)
        } else {
            didEndLifecycle = pipelineLifecycle.failCurrent()
        }
        guard didEndLifecycle, isRunning || isStarting else { return }

        finishPipeline(statusOverride: error.localizedDescription)
    }

    private func handleSystemAudioCaptureStoppedByUser(generation: UInt64) {
        guard pipelineLifecycle.fail(generation: generation),
              isRunning || isStarting
        else {
            return
        }

        finishPipeline(statusOverride: nil)
    }

    private func handleCaptureStartFailure(
        _ error: Error,
        generation: UInt64,
        configuration: StartConfiguration
    ) async {
        if configuration.audioInputSource == .systemAudio,
           SystemAudioCapture.isUserStoppedError(error) {
            handleSystemAudioCaptureStoppedByUser(generation: generation)
            return
        }

        guard pipelineLifecycle.fail(generation: generation) else {
            // A capture/provider callback already ended this generation.
            return
        }
        finishPipeline(statusOverride: AppText.startFailed(error.localizedDescription))
    }

    func pause() {
        guard isRunning, !isPaused else { return }

        flushPendingRecognizedCaption()
        flushPendingCaptionPresentation()
        transcriptCleanupTask?.cancel()
        transcriptCleanupTask = nil
        commitCurrentPartial()
        organizeCurrentTranscript(sourceTextOverride: visibleTranscript())
        setCaptionersPaused(true)
        isPaused = true
        statusMessage = AppText.paused
    }

    func resume() {
        guard isRunning, isPaused else { return }

        setCaptionersPaused(false)
        isPaused = false
        lastRecognitionAt = Date()
        statusMessage = AppText.listeningForSpeech(from: audioInputSource)
    }

    func openPrivacySettings() {
        openPrivacySettings(audioInputSource == .microphone ? .microphone : .screenRecording)
    }

    func openPrivacySettings(_ pane: PrivacySettingsPane) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.anchor)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func refreshMicrophoneInputDevices() {
        microphoneInputDevices = MicrophoneDeviceCatalog.availableInputDevices()
        if !microphoneInputDevices.contains(where: { $0.id == selectedMicrophoneInputDeviceID }) {
            selectedMicrophoneInputDeviceID = MicrophoneInputDevice.systemDefaultID
        }
    }

    func refreshLocalTranslationConnection(updatesStatusMessage: Bool = true) {
        invalidateLocalConnectionCheck()
        let generation = localConnectionGeneration
        let configuration = localTranslationConfiguration
        localTranslationConnectionState = .checking
        localTranslationConnectionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.localConnectionGeneration == generation { self.localTranslationConnectionTask = nil }
            }
            do {
                try await localTranslator.checkConnection(configuration: configuration)
                try Task.checkCancellation()
                guard generation == localConnectionGeneration, configuration == localTranslationConfiguration else { return }
                localTranslationConnectionState = .available
                if updatesStatusMessage, !isRunning, !isStarting { statusMessage = AppText.localTranslationAvailable }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, generation == localConnectionGeneration,
                      configuration == localTranslationConfiguration else { return }
                localTranslationConnectionState = .unavailable(error.localizedDescription)
                if updatesStatusMessage { statusMessage = error.localizedDescription }
            }
        }
    }

    private func startAppleSpeechTranscriber(
        configuration: StartConfiguration,
        generation: UInt64
    ) async throws {
        // Keep this candidate entirely local until all cancellation and
        // generation checks pass. A non-cooperative speech-permission callback
        // from an older start must never replace or stop a newer pipeline.
        let candidate = LiveSpeechTranscriber()
        candidate.delegate = self
        do {
            // stopCaptioners() intentionally returns synchronously so Stop
            // never blocks MainActor. Before a replacement can reserve Speech
            // assets, suspend until the old analyzer has cancelled and all of
            // its locales have been released.
            await transcriber.stopAndWaitForCleanup()
            try Task.checkCancellation()
            try validatePipelineStart(generation: generation, configuration: configuration)

            let languages = [configuration.sourceLanguage]
            try Task.checkCancellation()
            try await candidate.start(languages: languages)
            try validatePipelineStart(generation: generation, configuration: configuration)

            stopCaptioners()
            transcriber = candidate
            transcriber.delegate = self
            activeCaptionerGeneration = generation
        } catch {
            candidate.delegate = nil
            candidate.stop()
            throw error
        }
    }

    private func resetLiveSessionState(clearsVisibleLines: Bool) {
        audioSampleCount = 0
        latestAudioLevel = nil
        lastRecognizedText = ""
        lastRecognizedWasFinal = false
        currentLineID = nil
        lastCaptionPresentationUpdateAt = Date.distantPast
        pendingCaptionPresentation = nil
        captionPresentationTask?.cancel()
        captionPresentationTask = nil
        pendingRecognizedCaption = nil
        recognizedCaptionDeliveryTask?.cancel()
        recognizedCaptionDeliveryTask = nil
        lastRecognizedCaptionDeliveryAt = Date.distantPast
        isLargeTranscriptRecognitionCoalescingActive = false
        committedSourceText = ""
        currentPartialText = ""
        currentPartialLanguage = nil
        pendingParagraphBreakBeforePartial = false
        floatingPresentationTask?.cancel()
        floatingPresentationTask = nil
        floatingCaptionHideTask?.cancel()
        floatingCaptionHideTask = nil
        isFloatingCaptionHiddenAfterSilence = false
        if clearsVisibleLines {
            sourceLanguageByLineID.removeAll()
            floatingCommittedSourceText = ""
            floatingCurrentPartialText = ""
            pendingFloatingParagraphBreakBeforePartial = false
            floatingPresentedSourceText = ""
            floatingQueuedSourceText = ""
            floatingPresentedAt = Date.distantPast
            floatingPresentedUnreadLength = 0
        } else {
            rehydrateFloatingCaptionDisplayFromCurrentLine()
        }
        pendingTranslationSourceText = ""
        latestTranslationRequest = nil
        translationBurstStartedAt = Date.distantPast
        if !clearsVisibleLines {
            clearPendingTranslationPlaceholders(message: AppText.translationCancelled)
        }
        resetTranslationCache()
        translationTaskGeneration += 1
        translationTask?.cancel()
        translationTask = nil
        transcriptCleanupTask?.cancel()
        transcriptCleanupTask = nil

        if clearsVisibleLines {
            lines.removeAll()
        }
    }

    private func clearPendingTranslationPlaceholders(message: String) {
        for index in lines.indices where lines[index].translatedText == AppText.translating {
            let line = lines[index]
            lines[index] = CaptionLine(
                id: line.id,
                sourceText: line.sourceText,
                translatedText: message,
                translatedSourceText: line.sourceText,
                createdAt: line.createdAt,
                isFinal: line.isFinal,
                revision: line.revision + 1,
                usesLongSessionDisplay: usesLongSessionMode
            )
        }

    }

    private func restoreSelectedSettings() {
        isRestoringSelectedSettings = true
        defer { isRestoringSelectedSettings = false }
        let defaults = preferences
        if let id = defaults.string(forKey: SettingsKey.sourceLanguageID), let language = LanguageOption.supported.first(where: { $0.id == id }) { sourceLanguage = language }
        if let id = defaults.string(forKey: SettingsKey.targetLanguageID), let language = LanguageOption.supported.first(where: { $0.id == id }) { targetLanguage = language }
        if sourceLanguage == targetLanguage { targetLanguage = sourceLanguage == .chineseSimplified ? .english : .chineseSimplified }
        if let url = defaults.string(forKey: SettingsKey.localTranslationBaseURLString), !url.isEmpty { localTranslationBaseURLString = url }
        if let model = defaults.string(forKey: SettingsKey.localTranslationModelID), !model.isEmpty {
            localTranslationModelID = LocalTranslationConfiguration.migratedModelID(model)
            defaults.set(localTranslationModelID, forKey: SettingsKey.localTranslationModelID)
        }
        if let id = defaults.string(forKey: SettingsKey.floatingCaptionDisplayMode), let mode = FloatingCaptionDisplayMode(rawValue: id) { floatingCaptionDisplayMode = mode }
        if let id = defaults.string(forKey: SettingsKey.floatingCaptionTextSize), let size = FloatingCaptionTextSize(rawValue: id) { floatingCaptionTextSize = size }
        if let id = defaults.string(forKey: SettingsKey.floatingCaptionLineCount), let count = Int(id), let lines = FloatingCaptionLineCount(rawValue: count) { floatingCaptionLineCount = lines }
        if defaults.object(forKey: SettingsKey.showsFloatingCaptionBackground) != nil { showsFloatingCaptionBackground = defaults.bool(forKey: SettingsKey.showsFloatingCaptionBackground) }
        if defaults.object(forKey: SettingsKey.keepsFloatingCaptionAboveOtherWindows) != nil { keepsFloatingCaptionAboveOtherWindows = defaults.bool(forKey: SettingsKey.keepsFloatingCaptionAboveOtherWindows) }
        if let id = defaults.string(forKey: SettingsKey.audioInputSource), let input = AudioInputSource(rawValue: id) { audioInputSource = input }
        if let id = defaults.string(forKey: SettingsKey.selectedMicrophoneInputDeviceID) { selectedMicrophoneInputDeviceID = id }
        refreshMicrophoneInputDevices()
    }

    private func persistSelectedSettings() {
        guard !isRestoringSelectedSettings else { return }
        let defaults = preferences
        defaults.set(sourceLanguage.id, forKey: SettingsKey.sourceLanguageID)
        defaults.set(targetLanguage.id, forKey: SettingsKey.targetLanguageID)
        defaults.set(localTranslationBaseURLString, forKey: SettingsKey.localTranslationBaseURLString)
        defaults.set(localTranslationModelID, forKey: SettingsKey.localTranslationModelID)
        defaults.set(floatingCaptionDisplayMode.id, forKey: SettingsKey.floatingCaptionDisplayMode)
        defaults.set(floatingCaptionTextSize.id, forKey: SettingsKey.floatingCaptionTextSize)
        defaults.set(floatingCaptionLineCount.id, forKey: SettingsKey.floatingCaptionLineCount)
        defaults.set(showsFloatingCaptionBackground, forKey: SettingsKey.showsFloatingCaptionBackground)
        defaults.set(keepsFloatingCaptionAboveOtherWindows, forKey: SettingsKey.keepsFloatingCaptionAboveOtherWindows)
        defaults.set(audioInputSource.id, forKey: SettingsKey.audioInputSource)
        defaults.set(selectedMicrophoneInputDeviceID, forKey: SettingsKey.selectedMicrophoneInputDeviceID)
    }

    private func stopCapture() async {
        await systemAudioCapture.stop()
        await microphoneAudioCapture.stop()
    }

    private func floatingCaptionText(from text: String?) -> String {
        guard let text else { return "" }

        return text.floatingCaptionTail(
            maxLines: floatingCaptionLineCount.rawValue,
            lineWidthUnits: floatingCaptionTextSize.floatingLineWidthUnits
        )
    }

    private func appendCaption(
        sourceText: String,
        recognizedLanguage: LanguageOption,
        confidence: Double,
        isFinal: Bool
    ) {
        guard isRunning, !isPaused else { return }
        guard sourceText != lastRecognizedText || isFinal != lastRecognizedWasFinal else { return }

        let now = Date()
        let hadLongSilence = now.timeIntervalSince(lastRecognitionAt) > paragraphBreakSilenceInterval
        let direction = translationDirection(recognizedLanguage: recognizedLanguage)

        let updatedSourceText = accumulatedTranscript(
            incoming: sourceText,
            hadLongSilence: hadLongSilence,
            isFinal: isFinal,
            language: direction.source
        )
        guard !updatedSourceText.isEmpty else { return }

        lastRecognizedText = sourceText
        lastRecognizedWasFinal = isFinal
        lastRecognitionAt = now
        transcriptCleanupTask?.cancel()

        if let currentLineID,
           let index = lines.firstIndex(where: { $0.id == currentLineID }) {
            let existingLine = lines[index]
            let sourceLanguageChanged = sourceLanguageByLineID[existingLine.id] != direction.source
            sourceLanguageByLineID[existingLine.id] = direction.source
            guard updatedSourceText != existingLine.sourceText || sourceLanguageChanged else { return }
            if sourceLanguageChanged, updatedSourceText == existingLine.sourceText {
                pendingTranslationSourceText = ""
                requestTranslation(for: existingLine, source: direction.source, target: direction.target)
                return
            }

            if shouldPresentCaptionUpdate(sourceText: updatedSourceText, isFinal: isFinal) {
                clearPendingCaptionPresentation()
                presentCaptionLineUpdate(
                    lineID: existingLine.id,
                    sourceText: updatedSourceText,
                    isFinal: isFinal,
                    source: direction.source,
                    target: direction.target
                )
            } else {
                scheduleCaptionPresentation(
                    lineID: existingLine.id,
                    sourceText: updatedSourceText,
                    isFinal: isFinal,
                    source: direction.source,
                    target: direction.target
                )
            }
        } else {
            clearPendingCaptionPresentation()
            let line = CaptionLine(
                sourceText: updatedSourceText,
                translatedText: AppText.translating,
                createdAt: Date(),
                isFinal: isFinal,
                revision: 1,
                usesLongSessionDisplay: usesLongSessionMode
            )
            currentLineID = line.id
            sourceLanguageByLineID[line.id] = direction.source
            lines.append(line)
            lastCaptionPresentationUpdateAt = Date()
            requestTranslation(for: line, source: direction.source, target: direction.target)
        }
    }

    private func enqueueRecognizedCaption(
        sourceText: String,
        recognizedLanguage: LanguageOption,
        confidence: Double
    ) {
        if !isLargeTranscriptRecognitionCoalescingActive {
            let currentSourceLength = lines.last?.sourceText.utf16.count ?? 0
            isLargeTranscriptRecognitionCoalescingActive = usesLongSessionMode
                || currentSourceLength >= Self.largeTranscriptPresentationCharacterLimit
                || sourceText.utf16.count >= Self.largeTranscriptPresentationCharacterLimit
        }

        guard isLargeTranscriptRecognitionCoalescingActive else {
            lastRecognizedCaptionDeliveryAt = Date()
            appendCaption(
                sourceText: sourceText,
                recognizedLanguage: recognizedLanguage,
                confidence: confidence,
                isFinal: false
            )
            return
        }

        pendingRecognizedCaption = PendingRecognizedCaption(
            sourceText: sourceText,
            recognizedLanguage: recognizedLanguage,
            confidence: confidence
        )
        guard recognizedCaptionDeliveryTask == nil else { return }

        let elapsed = Date().timeIntervalSince(lastRecognizedCaptionDeliveryAt)
        let delay = max(0, Self.largeTranscriptRecognitionDeliveryInterval - elapsed)
        guard delay > 0 else {
            flushPendingRecognizedCaption()
            return
        }

        recognizedCaptionDeliveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            guard !Task.isCancelled else { return }
            self?.flushPendingRecognizedCaption()
        }
    }

    private func flushPendingRecognizedCaption() {
        recognizedCaptionDeliveryTask?.cancel()
        recognizedCaptionDeliveryTask = nil
        guard let pendingRecognizedCaption else { return }

        self.pendingRecognizedCaption = nil
        lastRecognizedCaptionDeliveryAt = Date()
        appendCaption(
            sourceText: pendingRecognizedCaption.sourceText,
            recognizedLanguage: pendingRecognizedCaption.recognizedLanguage,
            confidence: pendingRecognizedCaption.confidence,
            isFinal: false
        )
    }

    private func shouldPresentCaptionUpdate(sourceText: String, isFinal: Bool) -> Bool {
        let sourceLength = sourceText.utf16.count
        guard sourceLength >= Self.largeTranscriptPresentationCharacterLimit else { return true }

        let elapsed = Date().timeIntervalSince(lastCaptionPresentationUpdateAt)
        let interval = isFinal
            ? Self.largeTranscriptPresentationInterval / 2
            : Self.largeTranscriptPresentationInterval
        return elapsed >= interval
    }

    private func scheduleCaptionPresentation(
        lineID: UUID,
        sourceText: String,
        isFinal: Bool,
        source: LanguageOption,
        target: LanguageOption
    ) {
        pendingCaptionPresentation = PendingCaptionPresentation(
            lineID: lineID,
            sourceText: sourceText,
            isFinal: isFinal,
            source: source,
            target: target
        )
        captionPresentationTask?.cancel()

        let elapsed = Date().timeIntervalSince(lastCaptionPresentationUpdateAt)
        let delay = max(0, Self.largeTranscriptPresentationInterval - elapsed)
        captionPresentationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            guard !Task.isCancelled else { return }
            flushPendingCaptionPresentation()
        }
    }

    private func flushPendingCaptionPresentation() {
        guard let pendingCaptionPresentation else { return }

        self.pendingCaptionPresentation = nil
        captionPresentationTask?.cancel()
        captionPresentationTask = nil
        presentCaptionLineUpdate(
            lineID: pendingCaptionPresentation.lineID,
            sourceText: pendingCaptionPresentation.sourceText,
            isFinal: pendingCaptionPresentation.isFinal,
            source: pendingCaptionPresentation.source,
            target: pendingCaptionPresentation.target
        )
    }

    private func clearPendingCaptionPresentation() {
        pendingCaptionPresentation = nil
        captionPresentationTask?.cancel()
        captionPresentationTask = nil
    }

    private func presentCaptionLineUpdate(
        lineID: UUID,
        sourceText: String,
        isFinal: Bool,
        source: LanguageOption,
        target: LanguageOption
    ) {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else { return }

        let existingLine = lines[index]
        guard sourceText != existingLine.sourceText || isFinal != existingLine.isFinal else { return }

        let line = CaptionLine(
            id: existingLine.id,
            sourceText: sourceText,
            translatedText: existingLine.translatedText,
            translatedSourceText: existingLine.translatedSourceText,
            createdAt: existingLine.createdAt,
            isFinal: isFinal,
            revision: existingLine.revision + 1,
            usesLongSessionDisplay: usesLongSessionMode
        )
        lines[index] = line
        lastCaptionPresentationUpdateAt = Date()
        requestTranslation(for: line, source: source, target: target)
    }

    private func accumulatedTranscript(
        incoming: String,
        hadLongSilence: Bool,
        isFinal: Bool,
        language: LanguageOption
    ) -> String {
        let trimmedIncoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIncoming.isEmpty else { return visibleTranscript() }

        if hadLongSilence, !currentPartialText.isEmpty {
            commitCurrentPartial()
            pendingParagraphBreakBeforePartial = !committedSourceText.isEmpty
            pendingFloatingParagraphBreakBeforePartial = !floatingCommittedSourceText.isEmpty
        }

        let incomingPartial = uncommittedIncomingText(
            from: trimmedIncoming,
            allowsCommittedRevision: !hadLongSilence,
            allowsCommittedReplay: !hadLongSilence,
            language: language
        )
        guard !incomingPartial.isEmpty else { return visibleTranscript() }

        if currentPartialText.isEmpty {
            currentPartialText = incomingPartial
            currentPartialLanguage = language
            setFloatingCurrentPartialText(incomingPartial)
            return visibleTranscript()
        }

        if currentPartialLanguage != language {
            commitCurrentPartial()
            pendingParagraphBreakBeforePartial = hadLongSilence && !committedSourceText.isEmpty
            pendingFloatingParagraphBreakBeforePartial = hadLongSilence && !floatingCommittedSourceText.isEmpty
            currentPartialText = incomingPartial
            currentPartialLanguage = language
            setFloatingCurrentPartialText(currentPartialText)
            return visibleTranscript()
        }

        if isRevisionOfCurrentPartial(incomingPartial) {
            currentPartialText = preferredPartialText(current: currentPartialText, incoming: incomingPartial)
            setFloatingCurrentPartialText(currentPartialText)
            return visibleTranscript()
        }

        if !hadLongSilence,
           !isFinal,
           isVolatileFragmentSuperseded(by: incomingPartial) {
            currentPartialText = incomingPartial
            setFloatingCurrentPartialText(currentPartialText)
            return visibleTranscript()
        }

        commitCurrentPartial()
        pendingParagraphBreakBeforePartial = hadLongSilence && !committedSourceText.isEmpty
        pendingFloatingParagraphBreakBeforePartial = hadLongSilence && !floatingCommittedSourceText.isEmpty
        currentPartialText = uncommittedIncomingText(
            from: trimmedIncoming,
            allowsCommittedRevision: true,
            allowsCommittedReplay: true,
            language: language
        )
        currentPartialLanguage = language
        setFloatingCurrentPartialText(currentPartialText)
        return visibleTranscript()
    }

    private func uncommittedIncomingText(
        from incoming: String,
        allowsCommittedRevision: Bool,
        allowsCommittedReplay: Bool,
        language: LanguageOption
    ) -> String {
        if allowsCommittedReplay,
           let replayTail = incomingTailAfterRecentCommittedReplay(incoming, language: language) {
            syncFloatingCommittedSourceTextToCommittedSourceText()
            return replayTail
        }

        if allowsCommittedReplay,
           TranscriptTextProcessor.committedTranscriptAlreadyMatches(incoming, in: committedSourceText) {
            return ""
        }

        if allowsCommittedRevision,
           replaceCommittedUnitsIfRevision(with: incoming, language: language, allowsBackfill: true) {
            syncFloatingCommittedSourceTextToCommittedSourceText()
            return ""
        }

        if let tail = incomingTailAfterCommittedText(
            incoming,
            allowsCommittedReplay: allowsCommittedReplay
        ) {
            return tail
        }

        return incoming
    }

    private func incomingTailAfterRecentCommittedReplay(_ incoming: String, language: LanguageOption) -> String? {
        guard let replay = TranscriptTextProcessor.incomingTailAfterRecentCommittedReplay(
            incoming,
            committedText: committedSourceText,
            languageID: language.id
        ) else {
            return nil
        }

        committedSourceText = replay.committedText
        return replay.tailText
    }

    private func incomingTailAfterCommittedText(
        _ incoming: String,
        allowsCommittedReplay: Bool
    ) -> String? {
        TranscriptTextProcessor.incomingTailAfterCommittedText(
            incoming,
            committedText: committedSourceText,
            allowsCommittedReplay: allowsCommittedReplay
        )
    }

    private func isRevisionOfCurrentPartial(_ incomingPartial: String) -> Bool {
        TranscriptTextProcessor.isRevisionOfCurrentPartial(
            current: currentPartialText,
            incoming: incomingPartial
        )
    }

    private func preferredPartialText(current: String, incoming: String) -> String {
        TranscriptTextProcessor.preferredPartialText(current: current, incoming: incoming)
    }

    private func isVolatileFragmentSuperseded(by incomingPartial: String) -> Bool {
        TranscriptTextProcessor.isVolatileFragmentSuperseded(
            current: currentPartialText,
            incoming: incomingPartial
        )
    }

    private func isWholeTextPrefix(_ prefix: String, of text: String) -> Bool {
        TranscriptTextProcessor.isWholeTextPrefix(prefix, of: text)
    }

    private func commitCurrentPartial() {
        let language = currentPartialLanguage ?? sourceLanguage
        let partial = organizeTranscript(currentPartialText, language: language)
        guard !partial.isEmpty else { return }

        var didAppendCommittedPartial = false
        var didReplaceCommittedPartial = false
        if committedSourceText.isEmpty {
            committedSourceText = partial
            didAppendCommittedPartial = true
        } else if replaceCommittedUnitsIfRevision(with: partial, language: language, allowsBackfill: false) {
            // The speech recognizer can resend the last phrase with better wording after
            // cleanup. Treat that as a replacement, not a new line.
            didReplaceCommittedPartial = true
        } else if shouldAppendCommittedPartial(partial) {
            let separator = pendingParagraphBreakBeforePartial ? "\n\n" : "\n"
            committedSourceText += separator + partial
            didAppendCommittedPartial = true
        }
        pendingParagraphBreakBeforePartial = false
        currentPartialText = ""
        currentPartialLanguage = nil

        if didAppendCommittedPartial {
            commitFloatingCurrentPartial()
        } else if didReplaceCommittedPartial {
            syncFloatingCommittedSourceTextToCommittedSourceText(keepsCurrentPartial: false)
        } else {
            discardFloatingCurrentPartial()
        }
    }

    private func commitFloatingCurrentPartial() {
        let partial = floatingCurrentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !partial.isEmpty else { return }

        if floatingCommittedSourceText.isEmpty {
            floatingCommittedSourceText = partial
        } else if shouldAppendCommittedPartial(
            partial,
            to: floatingCommittedSourceText,
            pendingParagraphBreak: pendingFloatingParagraphBreakBeforePartial
        ) {
            let separator = pendingFloatingParagraphBreakBeforePartial ? "\n\n" : "\n"
            floatingCommittedSourceText += separator + partial
        }
        pendingFloatingParagraphBreakBeforePartial = false
        floatingCurrentPartialText = ""
        refreshFloatingCaptionPresentation()
    }

    private func setFloatingCurrentPartialText(_ text: String) {
        floatingCurrentPartialText = text
        refreshFloatingCaptionPresentation()
    }

    private func syncFloatingCommittedSourceTextToCommittedSourceText(keepsCurrentPartial: Bool = true) {
        floatingCommittedSourceText = committedSourceText
        if !keepsCurrentPartial {
            floatingCurrentPartialText = ""
            pendingFloatingParagraphBreakBeforePartial = false
        }
        refreshFloatingCaptionPresentation()
    }

    private func discardFloatingCurrentPartial() {
        floatingCurrentPartialText = ""
        pendingFloatingParagraphBreakBeforePartial = false
        refreshFloatingCaptionPresentation()
    }

    private func rehydrateFloatingCaptionDisplayFromCurrentLine() {
        guard let line = lines.last else {
            floatingCommittedSourceText = ""
            floatingCurrentPartialText = ""
            pendingFloatingParagraphBreakBeforePartial = false
            floatingPresentedSourceText = ""
            floatingQueuedSourceText = ""
            floatingPresentedAt = Date.distantPast
            floatingPresentedUnreadLength = 0
            return
        }

        floatingCommittedSourceText = line.sourceText
        floatingCurrentPartialText = ""
        pendingFloatingParagraphBreakBeforePartial = false
        floatingPresentedSourceText = line.sourceText
        floatingQueuedSourceText = ""
        floatingPresentedAt = Date()
        floatingPresentedUnreadLength = normalizedTranscriptForComparison(floatingPresentedSourceText).count

        noteFloatingCaptionActivity()
    }

    private func refreshFloatingCaptionPresentation() {
        let candidate = floatingVisibleSourceTranscript()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        noteFloatingCaptionActivity()

        if floatingPresentedSourceText.isEmpty {
            presentFloatingSourceText(candidate)
            return
        }

        let normalizedCandidate = normalizedTranscriptForComparison(candidate)
        let normalizedPresented = normalizedTranscriptForComparison(floatingPresentedSourceText)
        guard normalizedCandidate != normalizedPresented else { return }

        if isWholeTextPrefix(normalizedPresented, of: normalizedCandidate) {
            // Extensions keep the already-read text in place, so they can render
            // immediately. Keeping the dwell clock running prevents a stream of
            // extensions from postponing queued replacements forever.
            presentFloatingSourceText(candidate, resetsDwell: false)
            return
        }

        let now = Date()
        if canUpdateFloatingPresentationImmediately(now: now)
            || canAdvanceFloatingPresentation(now: now) {
            presentFloatingSourceText(candidate)
            return
        }

        floatingQueuedSourceText = candidate
        scheduleFloatingPresentationAdvance()
    }

    private func canUpdateFloatingPresentationImmediately(now: Date) -> Bool {
        now.timeIntervalSince(floatingPresentedAt) <= Self.floatingCaptionEarlyRevisionWindow
    }

    private func canAdvanceFloatingPresentation(now: Date = Date()) -> Bool {
        guard !floatingPresentedSourceText.isEmpty else { return true }
        return now.timeIntervalSince(floatingPresentedAt) >= floatingCaptionDwellDuration()
    }

    private func floatingCaptionDwellDuration() -> TimeInterval {
        let dwell = 0.9 + Double(floatingPresentedUnreadLength) / 28.0
        return min(
            max(Self.minimumFloatingCaptionDwell, dwell),
            Self.maximumFloatingCaptionDwell
        )
    }

    private func presentFloatingSourceText(_ text: String, resetsDwell: Bool = true) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let normalizedText = normalizedTranscriptForComparison(text)
        let normalizedPresented = normalizedTranscriptForComparison(floatingPresentedSourceText)
        let unreadLength = max(0, normalizedText.count - commonPrefixLength(normalizedPresented, normalizedText))
        floatingPresentedSourceText = text
        floatingQueuedSourceText = ""
        if resetsDwell {
            floatingPresentedAt = Date()
            floatingPresentedUnreadLength = unreadLength
        } else {
            floatingPresentedUnreadLength += unreadLength
        }
        noteFloatingCaptionActivity()
    }

    private func noteFloatingCaptionActivity() {
        isFloatingCaptionHiddenAfterSilence = false
        floatingCaptionHideTask?.cancel()
        floatingCaptionHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.floatingCaptionSilenceHideDelay))
            guard !Task.isCancelled, let self else { return }
            self.isFloatingCaptionHiddenAfterSilence = true
            self.floatingCaptionHideTask = nil
        }
    }

    private func scheduleFloatingPresentationAdvance() {
        floatingPresentationTask?.cancel()

        let remaining = max(
            0.05,
            floatingCaptionDwellDuration() - Date().timeIntervalSince(floatingPresentedAt)
        )
        let delayMilliseconds = max(50, Int(remaining * 1_000))
        floatingPresentationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled else { return }
            promoteQueuedFloatingPresentationIfReady()
        }
    }

    private func promoteQueuedFloatingPresentationIfReady() {
        guard canAdvanceFloatingPresentation() else {
            scheduleFloatingPresentationAdvance()
            return
        }

        if !floatingQueuedSourceText.isEmpty {
            presentFloatingSourceText(floatingQueuedSourceText)
        }

        if !floatingQueuedSourceText.isEmpty {
            scheduleFloatingPresentationAdvance()
        } else {
            floatingPresentationTask = nil
        }
    }

    private func replaceCommittedUnitsIfRevision(
        with text: String,
        language: LanguageOption,
        allowsBackfill: Bool
    ) -> Bool {
        guard let updatedText = TranscriptTextProcessor.committedTextByReplacingRevision(
            with: text,
            committedText: committedSourceText,
            languageID: language.id,
            allowsBackfill: allowsBackfill
        ) else {
            return false
        }

        committedSourceText = updatedText
        return true
    }

    private func shouldAppendCommittedPartial(_ partial: String) -> Bool {
        shouldAppendCommittedPartial(
            partial,
            to: committedSourceText,
            pendingParagraphBreak: pendingParagraphBreakBeforePartial
        )
    }

    private func shouldAppendCommittedPartial(
        _ partial: String,
        to committedText: String,
        pendingParagraphBreak: Bool
    ) -> Bool {
        TranscriptTextProcessor.shouldAppendCommittedPartial(
            partial,
            to: committedText,
            pendingParagraphBreak: pendingParagraphBreak
        )
    }

    private func normalizedTranscriptForComparison(_ text: String) -> String {
        TranscriptTextProcessor.normalizedForComparison(text)
    }

    private func visibleTranscript() -> String {
        let committed = committedSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let partial = currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !committed.isEmpty else {
            return partial
        }
        guard !partial.isEmpty else {
            return committed
        }

        let separator = pendingParagraphBreakBeforePartial ? "\n\n" : "\n"
        return committed + separator + partial
    }

    private func floatingVisibleSourceTranscript() -> String {
        let committed = floatingCommittedSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let partial = floatingCurrentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !committed.isEmpty else {
            return partial
        }
        guard !partial.isEmpty else {
            return committed
        }

        let separator = pendingFloatingParagraphBreakBeforePartial ? "\n\n" : "\n"
        return committed + separator + partial
    }

    private func scheduleTranscriptCleanup() {
        guard isRunning, currentLineID != nil else { return }
        guard Date().timeIntervalSince(lastRecognitionAt) > 1.5 else { return }

        if let pendingCleanup = transcriptCleanupTask, !pendingCleanup.isCancelled {
            return
        }
        transcriptCleanupTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            transcriptCleanupTask = nil
            organizeCurrentTranscript()
        }
    }

    private func organizeCurrentTranscript(sourceTextOverride: String? = nil) {

        if sourceTextOverride == nil {
            flushPendingCaptionPresentation()
        }

        guard isRunning,
              let currentLineID,
              let index = lines.firstIndex(where: { $0.id == currentLineID })
        else {
            return
        }

        let line = lines[index]
        let sourceText = sourceTextOverride ?? line.sourceText
        let sourceLanguage = sourceLanguageByLineID[line.id] ?? self.sourceLanguage
        let organizedSourceText = organizeTranscript(
            sourceText,
            language: sourceLanguage
        )
        let organizedTranslatedText = organizeTranslatedText(line.translatedText)
        let sourceChanged = organizedSourceText != line.sourceText
        let translationChanged = organizedTranslatedText != line.translatedText
        let needsTranslationRefresh = line.translatedSourceText != organizedSourceText

        if !sourceChanged,
           !translationChanged,
           needsTranslationRefresh,
           pendingTranslationSourceText == organizedSourceText {
            return
        }

        guard sourceChanged || translationChanged || needsTranslationRefresh else {
            return
        }

        committedSourceText = organizedSourceText
        currentPartialText = ""
        lines[index] = CaptionLine(
            id: line.id,
            sourceText: organizedSourceText,
            translatedText: organizedTranslatedText,
            translatedSourceText: line.translatedSourceText,
            createdAt: line.createdAt,
            isFinal: line.isFinal,
            revision: line.revision + 1,
            usesLongSessionDisplay: usesLongSessionMode
        )

        // Keep source captions stable while text cleanup revises the main pane.
        let updatedLine = lines[index]
        sourceLanguageByLineID[updatedLine.id] = sourceLanguage
        if updatedLine.translatedSourceText != updatedLine.sourceText {
            requestTranslation(for: updatedLine, source: sourceLanguage, target: targetLanguage)
        }
    }

    private func organizeTranslatedText(_ text: String) -> String {
        guard text != AppText.translating else { return text }
        return organizeTranscript(text, language: targetLanguage)
    }

    private func translateTranscript(
        _ text: String,
        source: LanguageOption,
        target: LanguageOption,
        progress: @escaping @MainActor @Sendable (String, String) -> Void = { _, _ in }
    ) async throws -> String {
        let paragraphSegments = try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return Self.translationSegmentGroups(from: text)
        }.value

        guard !paragraphSegments.isEmpty else { return "" }

        var translatedParagraphs: [String] = []
        var completedSourceParagraphs: [String] = []
        var consecutiveCacheHitCount = 0
        for segments in paragraphSegments {
            var translatedSegments: [String] = []
            var completedSourceSegments: [String] = []

            for segment in segments {
                try Task.checkCancellation()
                completedSourceSegments.append(segment)
                let cacheKey = translationCacheKey(segment: segment, source: source, target: target)
                if let cachedSegment = translationSegmentCache.value(forKey: cacheKey) {
                    consecutiveCacheHitCount += 1
                    if consecutiveCacheHitCount.isMultiple(of: Self.translationCacheHitYieldInterval) {
                        await Task.yield()
                        try Task.checkCancellation()
                    }
                    translatedSegments.append(cachedSegment)
                    continue
                }
                consecutiveCacheHitCount = 0

                let translatedSegment = try await translateSegment(segment, source: source, target: target)
                try Task.checkCancellation()
                let organizedSegment = organizeTranscript(translatedSegment, language: target)
                cacheTranslatedSegment(organizedSegment, forKey: cacheKey)
                translatedSegments.append(organizedSegment)

                let partialText = (translatedParagraphs + [translatedSegments.joined(separator: "\n")])
                    .joined(separator: "\n\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !partialText.isEmpty {
                    let completedSourceText = (completedSourceParagraphs + [completedSourceSegments.joined(separator: "\n")])
                        .joined(separator: "\n\n")
                    progress(partialText, completedSourceText)
                }
            }

            translatedParagraphs.append(translatedSegments.joined(separator: "\n"))
            completedSourceParagraphs.append(completedSourceSegments.joined(separator: "\n"))
        }

        return translatedParagraphs.joined(separator: "\n\n")
    }

    nonisolated private static func translationSegmentGroups(from text: String) -> [[String]] {
        TranscriptTextProcessor.paragraphParts(from: text)
            .map { translationSegments(from: $0) }
            .filter { !$0.isEmpty }
    }

    nonisolated private static func translationSegments(from paragraph: String) -> [String] {
        paragraph
            .split(separator: "\n", omittingEmptySubsequences: true)
            .flatMap { splitTranslationSegment(String($0)) }
    }

    nonisolated private static func splitTranslationSegment(_ text: String) -> [String] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return [] }
        guard trimmedText.utf16.count > 240 else { return [trimmedText] }

        var segments: [String] = []
        var current = ""

        for character in trimmedText {
            current.append(character)
            let shouldBreakAtSentence = ".!?。！？".contains(character)
                && current.utf16.count >= 80
            let shouldBreakAtWhitespace = character.isWhitespace
                && current.utf16.count >= 240

            if shouldBreakAtSentence || shouldBreakAtWhitespace {
                let segment = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !segment.isEmpty {
                    segments.append(segment)
                }
                current = ""
            }
        }

        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            segments.append(tail)
        }
        return segments
    }

    private func translationCacheKey(segment: String, source: LanguageOption, target: LanguageOption) -> String {
        "\(source.id)\t\(target.id)\t\(translationEngineCacheID)\t\(segment)"
    }

    private func cacheTranslatedSegment(_ segment: String, forKey key: String) {
        translationSegmentCache.insert(segment, forKey: key)
    }

    private func resetTranslationCache() {
        translationSegmentCache.removeAll()
    }

    private func requestTranslation(for line: CaptionLine, source: LanguageOption, target: LanguageOption) {

        guard source.id != target.id else {
            markTranslationUnavailable(
                AppText.sameLanguageTranslationUnavailable,
                for: line,
                matching: line.sourceText
            )
            return
        }

        let sourceText = line.sourceText
        guard pendingTranslationSourceText != sourceText else { return }
        pendingTranslationSourceText = sourceText
        if latestTranslationRequest == nil {
            translationBurstStartedAt = Date()
        }
        latestTranslationRequest = TranslationRequest(
            line: line,
            sourceText: sourceText,
            translationSourceText: sourceText,
            source: source,
            target: target
        )

        guard translationTask == nil else {
            return
        }

        translationTaskGeneration += 1
        let generation = translationTaskGeneration
        translationTask = Task { @MainActor in
            await processPendingTranslationRequests(generation: generation)
        }
    }

    private func processPendingTranslationRequests(generation: Int) async {
        while !Task.isCancelled, let request = latestTranslationRequest {
            latestTranslationRequest = nil

            do {
                let delay = translationDebounceDelay(for: request.sourceText)
                if delay > 0 {
                    try await Task.sleep(for: .milliseconds(delay))
                }

                if latestTranslationRequest != nil {
                    continue
                }

                translationBurstStartedAt = .distantPast
                let translationSourceText = try await preparedTranslationSourceText(
                    request.translationSourceText,
                    language: request.source
                )
                try Task.checkCancellation()
                if latestTranslationRequest != nil {
                    continue
                }
                let translatedText = try await translateTranscript(
                    translationSourceText,
                    source: request.source,
                    target: request.target,
                    progress: { [weak self] partialText, completedSourceText in
                        guard let self, generation == self.translationTaskGeneration else { return }
                        self.updateTranslation(
                            partialText,
                            for: request.line,
                            matching: request.sourceText,
                            translatedSourceText: completedSourceText,
                            finalizesRequest: false
                        )
                    }
                )
                try Task.checkCancellation()
                guard generation == translationTaskGeneration else { return }
                updateTranslation(translatedText, for: request.line, matching: request.sourceText)
            } catch is CancellationError {
                // A cancelled loop can resume after a newer loop was registered;
                // only clear its own registration to avoid spawning a concurrent loop.
                if generation == translationTaskGeneration {
                    translationTask = nil
                }
                return
            } catch {
                guard generation == translationTaskGeneration else { return }
                if pendingTranslationSourceText == request.sourceText {
                    pendingTranslationSourceText = ""
                }
                markTranslationUnavailable(error.localizedDescription, for: request.line, matching: request.sourceText)
            }
        }

        if generation == translationTaskGeneration {
            translationTask = nil
        }
    }

    private func preparedTranslationSourceText(
        _ sourceText: String,
        language: LanguageOption
    ) async throws -> String {
        guard usesLongSessionMode else { return sourceText }

        let languageID = language.id
        let organizedSourceText = try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return TranscriptTextProcessor.organizeTranscript(sourceText, languageID: languageID)
        }.value
        guard !organizedSourceText.isEmpty else { return sourceText }
        return organizedSourceText
    }

    private func translationDebounceDelay(for sourceText: String) -> Int {
        if usesLongSessionMode {
            let sourceLength = sourceText.utf16.count
            if sourceLength >= Self.veryLargeTranscriptTranslationCharacterLimit {
                return 900
            }
            if sourceLength >= Self.largeTranscriptTranslationCharacterLimit {
                return 450
            }
        }

        guard translationBurstStartedAt != .distantPast else { return 45 }
        let burstAge = Date().timeIntervalSince(translationBurstStartedAt)
        return burstAge >= 0.45 ? 0 : 70
    }

    nonisolated static func isCompatibleLiveSource(current: String, requested: String) -> Bool {
        let currentText = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedText = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedText.isEmpty else { return currentText.isEmpty }
        if currentText == requestedText || currentText.hasPrefix(requestedText) {
            return true
        }

        let normalizedCurrentText = currentText.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let normalizedRequestedText = requestedText.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return normalizedCurrentText == normalizedRequestedText
            || normalizedCurrentText.hasPrefix(normalizedRequestedText)
    }

    private func updateTranslation(
        _ translatedText: String,
        for line: CaptionLine,
        matching sourceText: String,
        translatedSourceText: String? = nil,
        finalizesRequest: Bool = true
    ) {
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
        let currentSourceText = lines[index].sourceText
        // Fence against the whole requested revision even when the displayed
        // result only covers its completed source prefix.
        guard Self.isCompatibleLiveSource(current: currentSourceText, requested: sourceText) else {
            if finalizesRequest, pendingTranslationSourceText == sourceText {
                pendingTranslationSourceText = ""
            }
            return
        }
        let organizedTranslatedText = organizeTranscript(translatedText, language: targetLanguage)
        if finalizesRequest, pendingTranslationSourceText == sourceText {
            pendingTranslationSourceText = ""
        }

        lines[index] = CaptionLine(
            id: line.id,
            sourceText: currentSourceText,
            translatedText: organizedTranslatedText,
            translatedSourceText: translatedSourceText ?? sourceText,
            createdAt: line.createdAt,
            isFinal: line.isFinal,
            revision: lines[index].revision + 1,
            usesLongSessionDisplay: usesLongSessionMode
        )

        noteFloatingCaptionActivity()
    }

    private func markTranslationUnavailable(_ message: String, for line: CaptionLine, matching sourceText: String) {
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else {
            statusMessage = message
            return
        }
        let currentSourceText = lines[index].sourceText
        guard Self.isCompatibleLiveSource(current: currentSourceText, requested: sourceText) else {
            if lines[index].translatedText == AppText.translating {
                let line = lines[index]
                lines[index] = CaptionLine(
                    id: line.id,
                    sourceText: line.sourceText,
                    translatedText: message,
                    translatedSourceText: line.sourceText,
                    createdAt: line.createdAt,
                    isFinal: line.isFinal,
                    revision: line.revision + 1,
                    usesLongSessionDisplay: usesLongSessionMode
                )
            }
            statusMessage = message
            return
        }

        let existingTranslation = lines[index].translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !existingTranslation.isEmpty, existingTranslation != AppText.translating {
            if pendingTranslationSourceText == sourceText {
                pendingTranslationSourceText = ""
            }
            statusMessage = message
            return
        }

        if pendingTranslationSourceText == sourceText {
            pendingTranslationSourceText = ""
        }

        lines[index] = CaptionLine(
            id: line.id,
            sourceText: currentSourceText,
            translatedText: message,
            translatedSourceText: sourceText,
            createdAt: line.createdAt,
            isFinal: line.isFinal,
            revision: lines[index].revision + 1,
            usesLongSessionDisplay: usesLongSessionMode
        )
        noteFloatingCaptionActivity()
        statusMessage = message
    }

    private func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        var length = 0
        for (leftCharacter, rightCharacter) in zip(lhs, rhs) {
            guard leftCharacter == rightCharacter else { break }
            length += 1
        }
        return length
    }

    private func activeGeneration(
        for transcriber: LiveSpeechTranscriber,
        requiresRunning: Bool
    ) -> UInt64? {
        guard let generation = activeCaptionerGeneration else {
            // Presentation-policy tests and preview harnesses can intentionally
            // drive the delegate while manually owning `isRunning`. Production
            // starts always publish a captioner generation before setting it.
            guard requiresRunning,
                  isRunning,
                  pipelineLifecycle.phase == .stopped
            else {
                return nil
            }
            return pipelineLifecycle.generation
        }
        let isCurrentProducer = transcriber === self.transcriber
        guard isCurrentProducer else { return nil }
        if requiresRunning {
            return pipelineLifecycle.acceptsSample(generation: generation) ? generation : nil
        }
        return pipelineLifecycle.isActive(generation: generation) ? generation : nil
    }

    var selectedMicrophoneDevice: MicrophoneInputDevice {
        microphoneInputDevices.first { $0.id == selectedMicrophoneInputDeviceID }
            ?? .systemDefault
    }

    var localTranslationConfiguration: LocalTranslationConfiguration {
        LocalTranslationConfiguration(
            baseURLString: localTranslationBaseURLString,
            modelID: localTranslationModelID
        )
    }

    var floatingSourceText: String {
        guard !isFloatingCaptionHiddenAfterSilence else { return "" }

        // A bilingual caption must use the source snapshot that produced the
        // visible translation, even while recognition has already moved ahead.
        if floatingCaptionDisplayMode == .originalAndTranslation,
           let line = floatingTranslatedLine {
            let sourceText = line.translatedSourceText.isEmpty ? line.sourceText : line.translatedSourceText
            return floatingCaptionText(from: sourceText)
        }

        let displayText = floatingPresentedSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayText.isEmpty {
            return floatingCaptionText(from: displayText)
        }

        let liveDisplayText = floatingVisibleSourceTranscript()
        if !liveDisplayText.isEmpty {
            return floatingCaptionText(from: liveDisplayText)
        }

        return floatingCaptionText(from: lines.last?.sourceText)
    }

    var floatingTranslationText: String {
        guard !isFloatingCaptionHiddenAfterSilence,
              let line = floatingTranslatedLine
        else { return "" }

        // The transcript board and floating window share the accepted result.
        // A separate dwell queue can lag, discard revisions, or replay old text.
        return floatingCaptionText(from: line.translatedText)
    }

    private var floatingTranslatedLine: CaptionLine? {
        guard let line = lines.last else { return nil }
        let text = line.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != AppText.translating else { return nil }
        return line
    }

    var hasFloatingCaptionContent: Bool {
        !floatingSourceText.isEmpty || !floatingTranslationText.isEmpty
    }

#if DEBUG
    func beginPermissionSuspendedStartForTesting() -> UInt64? {
        guard !isRunning, !isStarting else { return nil }

        invalidateCaptureStartAttempt()
        let configuration = currentStartConfiguration()
        let generation = pipelineLifecycle.beginStart(configuration: configuration)
        activeCaptureStartGeneration = generation
        isStarting = true
        statusMessage = AppText.checkingSpeechPermission
        captureStartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.completeCaptureStartAttempt(generation: generation) }
            do {
                await withCheckedContinuation { continuation in
                    self.permissionSuspendedStartContinuations[generation] = continuation
                }
                self.permissionSuspendedStartContinuations[generation] = nil
                try self.validatePipelineStart(
                    generation: generation,
                    configuration: configuration
                )
            } catch let error as CancellationError {
                await self.handleCancelledCaptureStart(
                    generation: generation,
                    error: error
                )
            } catch {
                guard self.pipelineLifecycle.fail(generation: generation) else { return }
                self.isStarting = false
                self.isRunning = false
                self.stopCaptioners()
                await self.stopCapture()
                self.statusMessage = AppText.startFailed(error.localizedDescription)
            }
        }
        return generation
    }

    func resumePermissionSuspendedStartForTesting() {
        guard permissionSuspendedStartContinuations.count == 1,
              let generation = permissionSuspendedStartContinuations.keys.first
        else {
            return
        }
        resumePermissionSuspendedStartForTesting(generation: generation)
    }

    func resumePermissionSuspendedStartForTesting(generation: UInt64) {
        let continuation = permissionSuspendedStartContinuations.removeValue(forKey: generation)
        continuation?.resume()
    }

    var isPermissionSuspendedStartForTesting: Bool {
        !permissionSuspendedStartContinuations.isEmpty
    }

    func isPermissionSuspendedStartForTesting(generation: UInt64) -> Bool {
        permissionSuspendedStartContinuations[generation] != nil
    }

    func simulatePipelineStartConfigurationErrorForTesting(
        generation: UInt64
    ) async {
        await handlePipelineStartError(
            .configurationChanged,
            generation: generation
        )
    }

    func activateLiveCallbackPipelineForTesting() -> (
        generation: UInt64,
        transcriber: LiveSpeechTranscriber
    ) {
        pipelineLifecycle.stop()
        stopCaptioners()
        resetLiveSessionState(clearsVisibleLines: true)

        let configuration = currentStartConfiguration()
        let generation = pipelineLifecycle.beginStart(configuration: configuration)
        transcriber = LiveSpeechTranscriber()
        transcriber.delegate = self
        activeCaptionerGeneration = generation
        _ = pipelineLifecycle.markRunning(
            generation: generation,
            currentConfiguration: configuration
        )
        isStarting = false
        isRunning = true
        return (generation, transcriber)
    }

    var systemAudioCaptureForTesting: SystemAudioCapture {
        systemAudioCapture
    }

    func simulateSystemAudioStartFailureForTesting(_ error: Error) async -> UInt64? {
        guard !isRunning, !isStarting, audioInputSource == .systemAudio else {
            return nil
        }

        let configuration = currentStartConfiguration()
        let generation = pipelineLifecycle.beginStart(configuration: configuration)
        activeCaptureStartGeneration = generation
        isStarting = true
        statusMessage = AppText.startingCapture(for: .systemAudio)
        await handleCaptureStartFailure(
            error,
            generation: generation,
            configuration: configuration
        )
        completeCaptureStartAttempt(generation: generation)
        return generation
    }

    func acceptTranslationForTesting(_ text: String, for line: CaptionLine, sourceText: String) {
        updateTranslation(text, for: line, matching: sourceText)
    }
#endif
}

extension TranslationSessionStore: SystemAudioCaptureDelegate {
    nonisolated func systemAudioCapture(
        _ capture: SystemAudioCapture,
        didOutput sampleBuffer: CMSampleBuffer,
        generation: UInt64
    ) {
        audioSamplePipelineRegistry.append(sampleBuffer, generation: generation)
    }

    nonisolated func systemAudioCapture(
        _ capture: SystemAudioCapture,
        didReceiveAudioSampleCount count: Int,
        level: Float?,
        generation: UInt64
    ) {
        Task { @MainActor in
            guard capture === systemAudioCapture,
                  pipelineLifecycle.acceptsSample(generation: generation)
            else {
                return
            }
            audioSampleCount = count
            latestAudioLevel = level
            guard !isPaused else {
                statusMessage = AppText.paused
                return
            }
            if isRunning, lines.isEmpty {
                statusMessage = audioStatusMessage(sampleCount: count, level: level)
            }
            if let level, level < -50 {
                scheduleTranscriptCleanup()
            }
        }
    }

    nonisolated func systemAudioCapture(
        _ capture: SystemAudioCapture,
        didFail error: Error,
        generation: UInt64
    ) {
        Task { @MainActor in
            guard capture === systemAudioCapture else { return }
            handleFatalPipelineError(error, generation: generation)
        }
    }

    nonisolated func systemAudioCaptureDidStopByUser(
        _ capture: SystemAudioCapture,
        generation: UInt64
    ) {
        Task { @MainActor in
            guard capture === systemAudioCapture else { return }
            handleSystemAudioCaptureStoppedByUser(generation: generation)
        }
    }

    private func audioStatusMessage(sampleCount: Int, level: Float?) -> String {
        guard let level else {
            return AppText.receivingAudioWaiting(sampleCount: sampleCount, source: audioInputSource)
        }

        let roundedLevel = Int(level.rounded())
        if level < -55 {
            return AppText.receivingSilentAudio(
                sampleCount: sampleCount,
                level: roundedLevel,
                source: audioInputSource
            )
        }

        return AppText.receivingAudioTranscribing(
            sampleCount: sampleCount,
            level: roundedLevel,
            source: audioInputSource
        )
    }
}

extension TranslationSessionStore: MicrophoneAudioCaptureDelegate {
    nonisolated func microphoneAudioCapture(
        _ capture: MicrophoneAudioCapture,
        didOutput sampleBuffer: CMSampleBuffer,
        generation: UInt64
    ) {
        audioSamplePipelineRegistry.append(sampleBuffer, generation: generation)
    }

    nonisolated func microphoneAudioCapture(
        _ capture: MicrophoneAudioCapture,
        didReceiveAudioSampleCount count: Int,
        level: Float?,
        generation: UInt64
    ) {
        Task { @MainActor in
            guard capture === microphoneAudioCapture,
                  pipelineLifecycle.acceptsSample(generation: generation)
            else {
                return
            }
            audioSampleCount = count
            latestAudioLevel = level
            guard !isPaused else {
                statusMessage = AppText.paused
                return
            }
            if isRunning, lines.isEmpty {
                statusMessage = audioStatusMessage(sampleCount: count, level: level)
            }
            if let level, level < -50 {
                scheduleTranscriptCleanup()
            }
        }
    }

    nonisolated func microphoneAudioCapture(
        _ capture: MicrophoneAudioCapture,
        didFail error: Error,
        generation: UInt64
    ) {
        Task { @MainActor in
            guard capture === microphoneAudioCapture else { return }
            handleFatalPipelineError(error, generation: generation)
        }
    }
}

extension TranslationSessionStore: LiveSpeechTranscriberDelegate {
    nonisolated func liveSpeechTranscriber(
        _ transcriber: LiveSpeechTranscriber,
        didRecognize text: String,
        language: LanguageOption,
        confidence: Double
    ) {
        Task { @MainActor in
            guard activeGeneration(for: transcriber, requiresRunning: true) != nil else {
                return
            }
            enqueueRecognizedCaption(
                sourceText: text,
                recognizedLanguage: language,
                confidence: confidence
            )
        }
    }
    nonisolated func liveSpeechTranscriber(_ transcriber: LiveSpeechTranscriber, didFail error: Error) {
        Task { @MainActor in
            guard let generation = activeGeneration(
                for: transcriber,
                requiresRunning: false
            ) else {
                return
            }
            handleFatalPipelineError(error, generation: generation)
        }
    }
}

private struct LocalRuntimeFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
