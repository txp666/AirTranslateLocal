import Foundation
import Testing
@testable import AirTranslate

@Suite
@MainActor
struct LocalConnectionCancellationTests {
    @Test
    func cancellingSuspendedStartRechecksConnectionAndEnablesStartAgain() async throws {
        let transportConfiguration = URLSessionConfiguration.ephemeral
        transportConfiguration.protocolClasses = [SuspendedLocalConnectionURLProtocol.self]
        let transport = URLSession(configuration: transportConfiguration)
        defer { transport.invalidateAndCancel() }
        let session = TranslationSessionStore(
            preferences: InMemoryUserDefaults(),
            localTranslator: LocalTranslationService(session: transport),
            speechAvailabilityProvider: { _ in ModelAvailability(state: .installed, detail: "Installed") }
        )
        defer { session.prepareForTermination() }
        session.localTranslationModelID = "test-model"
        session.prepareLocalModel()
        try #require(await eventually { session.canStartTranslation })

        // The runtime's first /models request attached successfully. Hold the
        // real start preflight in URLSession, before any permission/audio work.
        session.start()
        try #require(await eventually { SuspendedLocalConnectionURLProtocol.requests.isPending(2) })
        #expect(session.isStarting)
        #expect(session.localTranslationConnectionState == .checking)

        session.stop()
        try #require(await eventually {
            SuspendedLocalConnectionURLProtocol.requests.wasCancelled(2)
                && SuspendedLocalConnectionURLProtocol.requests.isPending(3)
        })
        #expect(!session.isStarting)
        #expect(!session.isRunning)
        #expect(!session.canStartTranslation)

        SuspendedLocalConnectionURLProtocol.requests.complete(3)
        try #require(await eventually { session.canStartTranslation })
        #expect(session.localModelRuntimeState == .ready)
        #expect(session.localTranslationConnectionState == .available)
        #expect(session.statusMessage == AppText.stopped)
        #expect(!session.isStarting)
        #expect(!session.isRunning)
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

private final class SuspendedConnectionRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var requestCount = 0
    private var pending: [Int: SuspendedLocalConnectionURLProtocol] = [:]
    private var cancelled = Set<Int>()

    func begin(_ request: SuspendedLocalConnectionURLProtocol) -> Int {
        lock.withLock {
            requestCount += 1
            if requestCount > 1 { pending[requestCount] = request }
            return requestCount
        }
    }

    func isPending(_ number: Int) -> Bool {
        lock.withLock { pending[number] != nil }
    }

    func wasCancelled(_ number: Int) -> Bool {
        lock.withLock { cancelled.contains(number) }
    }

    func cancel(_ request: SuspendedLocalConnectionURLProtocol) {
        lock.withLock {
            guard let number = pending.first(where: { $0.value === request })?.key else { return }
            pending[number] = nil
            cancelled.insert(number)
        }
    }

    func complete(_ number: Int) {
        let request = lock.withLock { pending.removeValue(forKey: number) }
        request?.complete()
    }
}

private final class SuspendedLocalConnectionURLProtocol: URLProtocol, @unchecked Sendable {
    static let requests = SuspendedConnectionRequests()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if Self.requests.begin(self) == 1 { complete() }
    }

    override func stopLoading() { Self.requests.cancel(self) }

    func complete() {
        guard let url = request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"data":[{"id":"test-model"}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
