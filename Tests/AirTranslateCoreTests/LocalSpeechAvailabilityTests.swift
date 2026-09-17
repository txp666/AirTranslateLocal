import Foundation
import Testing
@testable import AirTranslate

@MainActor
private final class ControlledSpeechAssets {
    private(set) var checkedLanguages: [LanguageOption] = []
    private(set) var downloadedLanguages: [LanguageOption] = []
    private var checks: [CheckedContinuation<ModelAvailability, Never>?] = []
    private var downloads: [CheckedContinuation<Void, Error>?] = []
    private(set) var installed: Set<String> = []

    func check(_ language: LanguageOption) async -> ModelAvailability {
        checkedLanguages.append(language)
        return await withCheckedContinuation { checks.append($0) }
    }

    func finishCheck(_ index: Int, state: ModelAvailabilityState, detail: String) {
        guard checks.indices.contains(index), let continuation = checks[index] else { return }
        checks[index] = nil
        continuation.resume(returning: ModelAvailability(state: state, detail: detail))
    }

    func download(_ language: LanguageOption) async throws {
        downloadedLanguages.append(language)
        try await withCheckedThrowingContinuation { downloads.append($0) }
    }

    func finishDownload(_ index: Int, succeeds: Bool) {
        guard downloads.indices.contains(index), let continuation = downloads[index] else { return }
        downloads[index] = nil
        if succeeds {
            installed.insert(downloadedLanguages[index].id)
            continuation.resume()
        } else {
            continuation.resume(throwing: URLError(.cancelled))
        }
    }
}

@Suite
@MainActor
struct LocalSpeechAvailabilityTests {
    @Test
    func lateAvailabilityForPreviousLanguageCannotOverwriteCurrentLanguage() async throws {
        let assets = ControlledSpeechAssets()
        let session = TranslationSessionStore(
            preferences: InMemoryUserDefaults(),
            speechAvailabilityProvider: { await assets.check($0) }
        )
        try #require(await eventually { assets.checkedLanguages.count == 1 })
        session.useQuickSourceLanguage(.japanese)
        try #require(await eventually { assets.checkedLanguages.count == 2 })
        assets.finishCheck(1, state: .installed, detail: "Japanese installed")
        try #require(await eventually { session.speechAvailability.detail == "Japanese installed" })
        assets.finishCheck(0, state: .unavailable, detail: "Old English result")
        for _ in 0..<10 { await Task.yield() }
        #expect(session.sourceLanguage == .japanese)
        #expect(session.speechAvailability.state == .installed)
        #expect(session.speechAvailability.detail == "Japanese installed")
    }

    @Test
    func cancelledLanguageDownloadCannotClearOrFailReplacementDownload() async throws {
        let assets = ControlledSpeechAssets()
        let session = TranslationSessionStore(
            preferences: InMemoryUserDefaults(),
            speechAvailabilityProvider: { language in
                ModelAvailability(state: assets.installed.contains(language.id) ? .installed : .downloadRequired, detail: language.id)
            },
            speechAssetDownloader: { try await assets.download($0) }
        )
        try #require(await eventually { session.speechAvailability.state == .downloadRequired })
        session.downloadSpeechAssets()
        try #require(await eventually { assets.downloadedLanguages.count == 1 })
        session.useQuickSourceLanguage(.japanese)
        try #require(await eventually { session.speechAvailability.state == .downloadRequired })
        session.downloadSpeechAssets()
        try #require(await eventually { assets.downloadedLanguages.count == 2 })
        assets.finishDownload(0, succeeds: false)
        for _ in 0..<10 { await Task.yield() }
        #expect(session.speechAvailability.state == .downloading)
        session.downloadSpeechAssets()
        #expect(assets.downloadedLanguages.count == 2)
        assets.finishDownload(1, succeeds: true)
        try #require(await eventually { session.speechAvailability.state == .installed })
        #expect(session.sourceLanguage == .japanese)
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
