import Foundation
import Testing
@testable import AirTranslate

@Suite
struct LocalTranslationConfigurationTests {
    @Test
    func defaultsKeepTheVerifiedLocalModelAndLoopbackEndpoint() {
        #expect(LocalTranslationConfiguration.defaultModelID == "mlx-community/Hy-MT2-7B-8bit")
        #expect(LocalTranslationConfiguration.defaultBaseURLString == "http://127.0.0.1:8080/v1")
    }

    @Test
    func customModelsArePreservedWhileTheLegacyDefaultMigrates() {
        #expect(LocalTranslationConfiguration.migratedModelID(" custom/local-model ") == "custom/local-model")
        #expect(LocalTranslationConfiguration.migratedModelID(" mlx-community/Hunyuan-MT-7B-4bit ") == LocalTranslationConfiguration.defaultModelID)
    }

    @Test
    func pastedConfigurationIsTrimmedWithoutChangingTheSelectedModel() {
        let configuration = LocalTranslationConfiguration(baseURLString: " http://localhost:9000/v1\n", modelID: " my-model\n")
        #expect(configuration.trimmedBaseURLString == "http://localhost:9000/v1")
        #expect(configuration.trimmedModelID == "my-model")
    }

    @Test
    func explicitRelativeAndHomePathsUseTheCanonicalServerModelID() {
        let relative = LocalTranslationConfiguration(baseURLString: "", modelID: "./Resources")
        let expected = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources").resolvingSymlinksInPath().path
        #expect(relative.trimmedModelID == expected)
        let home = LocalTranslationConfiguration(baseURLString: "", modelID: "~/")
        #expect(home.trimmedModelID == FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path)
        #expect(LocalTranslationConfiguration(baseURLString: "", modelID: "Resources").trimmedModelID == "Resources")
        #expect(LocalTranslationConfiguration(baseURLString: "", modelID: "mlx-community/model").trimmedModelID == "mlx-community/model")
    }

    @Test
    func symlinkedModelsMatchTheCanonicalIDAdvertisedByTheServer() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = directory.appendingPathComponent("model")
        let link = directory.appendingPathComponent("selected-model")
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: model)
        let configuration = LocalTranslationConfiguration(baseURLString: "", modelID: link.path)
        #expect(configuration.trimmedModelID == model.resolvingSymlinksInPath().path)
    }
}
