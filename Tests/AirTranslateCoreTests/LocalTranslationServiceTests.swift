import Foundation
import Testing
@testable import AirTranslate

@Suite
struct LocalTranslationServiceTests {
    @Test
    func endpointAppendsOpenAICompatiblePath() throws {
        let endpoint = try LocalTranslationService.endpoint(
            baseURLString: "http://127.0.0.1:8080/v1/",
            relativePath: "/chat/completions"
        )

        #expect(endpoint.absoluteString == "http://127.0.0.1:8080/v1/chat/completions")
    }

    @Test
    func endpointRejectsNonLoopbackHosts() {
        #expect(throws: LocalTranslationError.invalidLocalBaseURL) {
            try LocalTranslationService.endpoint(
                baseURLString: "https://example.com/v1",
                relativePath: "models"
            )
        }
    }

    @Test(arguments: [
        "http://user@localhost:8080/v1", "http://user:secret@127.0.0.1:8080/v1",
        "http://127.0.0.1.example.com/v1", "http://192.168.1.2/v1", "file:///tmp/models",
        "http://localhost:8080/v1?forward=remote", "http://localhost:8080/v1#fragment",
        "http://localhost:0/v1", "http://localhost:65536/v1"
    ])
    func endpointRejectsCredentialsAndNonLocalDestinations(address: String) {
        #expect(throws: LocalTranslationError.invalidLocalBaseURL) {
            try LocalTranslationService.endpoint(baseURLString: address, relativePath: "models")
        }
    }

    @Test
    func localhostUsesNumericLoopbackAndIPv6LoopbackIsSupported() throws {
        let local = try LocalTranslationService.endpoint(baseURLString: "http://localhost:8080/v1", relativePath: "models")
        let ipv6 = try LocalTranslationService.endpoint(baseURLString: "http://[::1]:8080/v1", relativePath: "models")
        #expect(local.host == "127.0.0.1")
        #expect(ipv6.absoluteString == "http://[::1]:8080/v1/models")
    }

    @Test
    func defaultTransportDisablesEverySystemProxyMechanism() throws {
        let configuration = LocalTranslationService.sessionConfiguration()
        let proxies = try #require(configuration.connectionProxyDictionary)
        for key in ["HTTPEnable", "HTTPSEnable", "SOCKSEnable", "ProxyAutoConfigEnable", "ProxyAutoDiscoveryEnable"] {
            #expect(proxies[key] as? Int == 0)
        }
        #expect(configuration.urlCache == nil)
    }

    @Test
    func injectedSessionStillSupportsLocalModelChecksAndTranslation() async throws {
        let service = LocalTranslationService(session: LocalTranslationTestSession.make())
        let configuration = LocalTranslationConfiguration(baseURLString: "http://127.0.0.1:8081/v1", modelID: "test-model")
        try await service.checkConnection(configuration: configuration)
        let result = try await service.translate("hello", source: .english, target: .chineseSimplified, configuration: configuration)
        #expect(result == "你好")
    }

    @Test(arguments: [8082, 8085])
    func redirectsAndChangedResponseDestinationsAreRejected(port: Int) async {
        let service = LocalTranslationService(session: LocalTranslationTestSession.make())
        let configuration = LocalTranslationConfiguration(baseURLString: "http://127.0.0.1:\(port)/v1", modelID: "test-model")
        await #expect(throws: LocalTranslationError.redirectNotAllowed) {
            try await service.translate("private caption", source: .english, target: .chineseSimplified, configuration: configuration)
        }
    }

    @Test
    func modelCheckRequiresTheConfiguredModel() async {
        let service = LocalTranslationService(session: LocalTranslationTestSession.make())
        let configuration = LocalTranslationConfiguration(baseURLString: "http://127.0.0.1:8081/v1", modelID: "another-model")
        await #expect(throws: LocalTranslationError.modelUnavailable) {
            try await service.checkConnection(configuration: configuration)
        }
    }

    @Test
    func translationRequestUsesChatCompletionsShape() throws {
        let request = try LocalTranslationService.makeTranslationRequest(
            text: "こんにちは",
            source: .japanese,
            target: .chineseSimplified,
            configuration: LocalTranslationConfiguration(
                baseURLString: LocalTranslationConfiguration.defaultBaseURLString,
                modelID: LocalTranslationConfiguration.defaultModelID
            )
        )
        let body = try #require(request.httpBody)
        let root = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(root["messages"] as? [[String: Any]])

        #expect(request.url?.path == "/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(root["model"] as? String == LocalTranslationConfiguration.defaultModelID)
        #expect(root["stream"] as? Bool == false)
        #expect(root["max_tokens"] as? Int == 512)
        #expect(root["temperature"] as? Double == 0.7)
        #expect(root["top_p"] as? Double == 0.6)
        #expect(root["top_k"] as? Int == 20)
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
        #expect((messages[0]["content"] as? String)?.contains("from Japanese into Chinese Simplified") == true)
        #expect((messages[0]["content"] as? String)?.hasSuffix("こんにちは") == true)
    }

    @Test
    func englishToChinesePromptUsesRequestedLanguagePair() {
        let prompt = LocalTranslationService.translationPrompt(
            text: "Good morning",
            source: .english,
            target: .chineseSimplified
        )

        #expect(prompt.contains("from English into Chinese Simplified"))
        #expect(prompt.contains("only output the translated result"))
        #expect(prompt.hasSuffix("Good morning"))
    }

    @Test
    func chatCompletionResponseDecodesTranslatedText() throws {
        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"你好"}}]}"#.utf8)

        let translation = try LocalTranslationService.decodeTranslation(from: data)

        #expect(translation == "你好")
    }

    @Test
    func modelListDecodesAvailableModelIDs() throws {
        let data = Data(
            #"{"object":"list","data":[{"id":"mlx-community/Hy-MT2-7B-8bit","object":"model"}]}"#.utf8
        )

        let modelIDs = try LocalTranslationService.decodeAvailableModelIDs(from: data)

        #expect(modelIDs == ["mlx-community/Hy-MT2-7B-8bit"])
    }

    @Test
    func emptyChatCompletionResponseIsRejected() {
        let data = Data(#"{"choices":[]}"#.utf8)

        #expect(throws: LocalTranslationError.emptyOutput) {
            try LocalTranslationService.decodeTranslation(from: data)
        }
    }
}

enum LocalTranslationTestSession {
    static func make() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LocalTranslationStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class LocalTranslationStubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let port = url.port ?? 0
        let responseURL = port == 8085 ? URL(string: "https://remote.invalid/completions")! : url
        let status = port == 8082 ? 302 : 200
        let headers = port == 8082 ? ["Location": "https://remote.invalid/completions"] : [:]
        let response = HTTPURLResponse(url: responseURL, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        let json = url.path.hasSuffix("models")
            ? #"{"data":[{"id":"test-model"}]}"#
            : #"{"choices":[{"message":{"role":"assistant","content":"你好"}}]}"#
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
