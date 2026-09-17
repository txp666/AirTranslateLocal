import Foundation

actor LocalTranslationService {
    private static let loopbackHosts = Set(["127.0.0.1", "localhost", "::1", "[::1]"])

    private let session: URLSession
    private let redirectDelegate = LocalTranslationRedirectDelegate()

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }

        self.session = URLSession(configuration: Self.sessionConfiguration())
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        // Local transcripts must never be handed to an HTTP, SOCKS, or PAC
        // proxy inherited from the user's system network settings.
        configuration.connectionProxyDictionary = [
            "HTTPEnable": 0,
            "HTTPSEnable": 0,
            "SOCKSEnable": 0,
            "ProxyAutoConfigEnable": 0,
            "ProxyAutoDiscoveryEnable": 0
        ]
        return configuration
    }

    func checkConnection(configuration: LocalTranslationConfiguration) async throws {
        guard !configuration.trimmedModelID.isEmpty else { throw LocalTranslationError.emptyModelID }
        let endpoint = try Self.endpoint(
            baseURLString: configuration.trimmedBaseURLString,
            relativePath: "models"
        )
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 2
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Self.requestError(statusCode: response.statusCode, data: data)
        }
        let availableModelIDs = try Self.decodeAvailableModelIDs(from: data)
        guard availableModelIDs.contains(configuration.trimmedModelID) else {
            throw LocalTranslationError.modelUnavailable
        }
    }

    func translate(
        _ text: String,
        source: LanguageOption,
        target: LanguageOption,
        configuration: LocalTranslationConfiguration
    ) async throws -> String {
        guard !text.isEmpty else { return text }

        let request = try Self.makeTranslationRequest(
            text: text,
            source: source,
            target: target,
            configuration: configuration
        )
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Self.requestError(statusCode: response.statusCode, data: data)
        }
        return try Self.decodeTranslation(from: data)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request, delegate: redirectDelegate)
            guard let response = response as? HTTPURLResponse else {
                throw LocalTranslationError.invalidResponse
            }
            guard !(300..<400).contains(response.statusCode), response.url == request.url else {
                throw LocalTranslationError.redirectNotAllowed
            }
            return (data, response)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LocalTranslationError {
            throw error
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw LocalTranslationError.connectionFailed
        }
    }

    static func endpoint(baseURLString: String, relativePath: String) throws -> URL {
        guard var components = URLComponents(string: baseURLString),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              loopbackHosts.contains(host)
        else {
            throw LocalTranslationError.invalidLocalBaseURL
        }
        guard components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65_535).contains($0) }) ?? true
        else {
            throw LocalTranslationError.invalidLocalBaseURL
        }
        // Avoid DNS/PAC changes turning the localhost name into a remote hop.
        if components.host?.lowercased() == "localhost" { components.host = "127.0.0.1" }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let childPath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, childPath].filter { !$0.isEmpty }.joined(separator: "/")

        guard let endpoint = components.url else {
            throw LocalTranslationError.invalidLocalBaseURL
        }
        return endpoint
    }

    static func makeTranslationRequest(
        text: String,
        source: LanguageOption,
        target: LanguageOption,
        configuration: LocalTranslationConfiguration
    ) throws -> URLRequest {
        let modelID = configuration.trimmedModelID
        guard !modelID.isEmpty else {
            throw LocalTranslationError.emptyModelID
        }

        let endpoint = try endpoint(
            baseURLString: configuration.trimmedBaseURLString,
            relativePath: "chat/completions"
        )
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 180
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            LocalChatCompletionRequest(
                model: modelID,
                messages: [
                    LocalChatMessage(
                        role: "user",
                        content: translationPrompt(text: text, source: source, target: target)
                    )
                ],
                maxTokens: 512,
                temperature: 0.7,
                topP: 0.6,
                topK: 20,
                stream: false
            )
        )
        return request
    }

    static func translationPrompt(
        text: String,
        source: LanguageOption,
        target: LanguageOption
    ) -> String {
        """
        Translate the following text from \(source.title) into \(target.title). Note that you should only output the translated result without any additional explanation:

        \(text)
        """
    }

    static func decodeTranslation(from data: Data) throws -> String {
        let response: LocalChatCompletionResponse
        do {
            response = try JSONDecoder().decode(LocalChatCompletionResponse.self, from: data)
        } catch {
            throw LocalTranslationError.invalidResponse
        }

        guard let text = response.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            throw LocalTranslationError.emptyOutput
        }
        return text
    }

    static func decodeAvailableModelIDs(from data: Data) throws -> Set<String> {
        do {
            let response = try JSONDecoder().decode(LocalModelsResponse.self, from: data)
            return Set(response.data.map(\.id))
        } catch {
            throw LocalTranslationError.invalidResponse
        }
    }

    private static func requestError(statusCode: Int, data: Data) -> LocalTranslationError {
        let response = try? JSONDecoder().decode(LocalServerErrorResponse.self, from: data)
        return .requestFailed(statusCode: statusCode, message: response?.error?.message)
    }
}

private final class LocalTranslationRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private struct LocalChatCompletionRequest: Encodable {
    let model: String
    let messages: [LocalChatMessage]
    let maxTokens: Int
    let temperature: Double
    let topP: Double
    let topK: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case topP = "top_p"
        case topK = "top_k"
        case stream
    }
}

private struct LocalChatMessage: Codable {
    let role: String
    let content: String
}

private struct LocalChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: LocalChatMessage
    }
}

private struct LocalServerErrorResponse: Decodable {
    let error: ErrorBody?

    struct ErrorBody: Decodable {
        let message: String?
    }
}

private struct LocalModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
    }
}

enum LocalTranslationError: LocalizedError, Equatable {
    case invalidLocalBaseURL
    case emptyModelID
    case modelUnavailable
    case connectionFailed
    case redirectNotAllowed
    case invalidResponse
    case emptyOutput
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidLocalBaseURL:
            AppText.localTranslationInvalidBaseURL
        case .emptyModelID:
            AppText.localTranslationEmptyModelID
        case .modelUnavailable:
            AppText.localTranslationModelUnavailable
        case .connectionFailed:
            AppText.localTranslationConnectionFailed
        case .redirectNotAllowed:
            LocalUI.text("模型服务返回了重定向，请使用直接的本机地址。", "The model server returned a redirect. Use its direct loopback address.")
        case .invalidResponse:
            AppText.localTranslationInvalidResponse
        case .emptyOutput:
            AppText.localTranslationEmptyOutput
        case let .requestFailed(statusCode, message):
            AppText.localTranslationRequestFailed(statusCode: statusCode, message: message)
        }
    }
}
