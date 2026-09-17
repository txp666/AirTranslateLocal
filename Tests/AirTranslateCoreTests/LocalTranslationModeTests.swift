import Foundation
import Testing
@testable import AirTranslate

@Suite(.serialized)
struct LocalTranslationModeTests {
    @Test
    @MainActor
    func freshInstallUsesLocalTranslationDefaults() {
        withIsolatedDefaults { defaults in
            let session = makeLocalTestSession(preferences: defaults)
            #expect(session.localTranslationBaseURLString == LocalTranslationConfiguration.defaultBaseURLString)
            #expect(session.localTranslationModelID == LocalTranslationConfiguration.defaultModelID)
            #expect(session.sourceLanguage == .english)
            #expect(session.targetLanguage == .chineseSimplified)
            #expect(session.shouldShowTranslationPane)
        }
    }

    @Test(arguments: ["gpt-live-transcribe", "gpt-realtime-translate", "gemini-3.5-live-translate-preview", "apple-system"])
    @MainActor
    func legacyProviderPreferencesCannotDisableLocalTranslation(_ legacy: String) {
        withIsolatedDefaults { defaults in
            defaults.set(legacy, forKey: "selectedModelID")
            defaults.set(legacy, forKey: "openAITranscriptionModelID")
            defaults.set(legacy, forKey: "openAITranslationModelID")
            defaults.set(legacy, forKey: "geminiTranslationModelID")
            defaults.set(false, forKey: "isLocalTranslationEnabled")
            defaults.set(true, forKey: "isDubbingEnabled")
            defaults.set("http://localhost:9000/v1", forKey: "localTranslationBaseURLString")
            defaults.set("local-test-model", forKey: "localTranslationModelID")
            let session = makeLocalTestSession(preferences: defaults)
            #expect(session.localTranslationBaseURLString == "http://localhost:9000/v1")
            #expect(session.localTranslationModelID == "local-test-model")
            #expect(session.shouldShowTranslationPane)
            #expect(session.availableFloatingCaptionDisplayModes == FloatingCaptionDisplayMode.allCases)
            #expect(session.sourceLanguage != session.targetLanguage)
        }
    }

    @Test
    @MainActor
    func legacyDefaultModelMigratesToHyMT2() {
        withIsolatedDefaults { defaults in
            defaults.set("mlx-community/Hunyuan-MT-7B-4bit", forKey: "localTranslationModelID")
            let session = makeLocalTestSession(preferences: defaults)
            #expect(session.localTranslationModelID == LocalTranslationConfiguration.defaultModelID)
            #expect(defaults.string(forKey: "localTranslationModelID") == LocalTranslationConfiguration.defaultModelID)
        }
    }

    @Test
    @MainActor
    func quickLanguageChangesAlwaysKeepDistinctSourceAndTarget() {
        let session = makeLocalTestSession()
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.useQuickSourceLanguage(.korean)
        #expect(session.sourceLanguage == .korean)
        #expect(session.targetLanguage != .korean)
        session.useQuickTargetLanguage(.korean)
        #expect(session.targetLanguage == .korean)
        #expect(session.sourceLanguage != .korean)
        let source = session.sourceLanguage
        session.swapQuickLanguagePair()
        #expect(session.sourceLanguage == .korean)
        #expect(session.targetLanguage == source)
        #expect(session.shouldShowTranslationPane)
    }

    @MainActor
    private func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
        body(InMemoryUserDefaults())
    }
}
