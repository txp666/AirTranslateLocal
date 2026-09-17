import Foundation
import Darwin
import Testing
@testable import AirTranslate

@Suite
struct LocalModelRuntimeManagerTests {
    @Test
    func standardRuntimePrecedesTheDeveloperVirtualEnvironment() throws {
        let projectRoot = URL(fileURLWithPath: "/tmp/AirTranslateLocal", isDirectory: true)
        let bundleURL = projectRoot.appendingPathComponent("dist/AirTranslate.app", isDirectory: true)

        let candidates = LocalModelRuntimeLocator.pythonCandidates(
            bundleURL: bundleURL,
            currentDirectoryURL: URL(fileURLWithPath: "/tmp/elsewhere", isDirectory: true),
            homeDirectoryURL: URL(fileURLWithPath: "/Users/test", isDirectory: true),
            environment: [:]
        )

        #expect(candidates.first?.standardizedFileURL.path == "/Users/test/Library/Application Support/AirTranslate/LocalMLX/.venv/bin/python")
        #expect(candidates.contains { $0.path == "/tmp/AirTranslateLocal/.venv/bin/python" })
    }

    @Test
    func environmentOverrideWinsWhenExecutable() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let overrideURL = temporaryDirectory.appendingPathComponent("python")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        #expect(FileManager.default.createFile(atPath: overrideURL.path, contents: Data()))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: overrideURL.path
        )

        let resolved = LocalModelRuntimeLocator.resolvePythonExecutable(
            bundleURL: URL(fileURLWithPath: "/Applications/AirTranslate.app", isDirectory: true),
            currentDirectoryURL: temporaryDirectory.appendingPathComponent("elsewhere"),
            homeDirectoryURL: temporaryDirectory.appendingPathComponent("home"),
            environment: ["AIRTRANSLATE_LOCAL_PYTHON": overrideURL.path]
        )

        #expect(resolved?.standardizedFileURL == overrideURL.standardizedFileURL)
    }

    @Test
    func watchdogCandidateUsesAppResourcesFirst() {
        let bundleURL = URL(fileURLWithPath: "/tmp/AirTranslate.app", isDirectory: true)
        let pythonURL = URL(fileURLWithPath: "/tmp/project/.venv/bin/python")

        let candidates = LocalModelRuntimeLocator.watchdogCandidates(
            bundleURL: bundleURL,
            pythonURL: pythonURL
        )

        #expect(
            candidates.first?.path
                == "/tmp/AirTranslate.app/Contents/Resources/local_mlx_watchdog.py"
        )
        #expect(candidates.contains { $0.path == "/tmp/project/Resources/local_mlx_watchdog.py" })
    }

    @Test
    func bootstrapDiscoveryDoesNotUseTheSystemInstallerStub() {
        let candidates = LocalModelRuntimeLocator.bootstrapPythonCandidates(environment: ["PATH": "/usr/bin:/custom/bin"])
        #expect(!candidates.contains { $0.path == "/usr/bin/python3" })
        #expect(candidates.contains { $0.path == "/custom/bin/python3" })
    }

    @Test
    @MainActor
    func anAlreadyRunningExternalServerIsReusedWithoutInstallingOrOwningIt() async throws {
        let service = LocalTranslationService(session: LocalTranslationTestSession.make())
        let runtime = LocalModelRuntimeManager(translator: service, environment: [:])
        let configuration = LocalTranslationConfiguration(baseURLString: "http://127.0.0.1:8081/v1", modelID: "test-model")
        var callbackReady = false
        var callbackError: String?
        runtime.startIfNeeded(configuration: configuration, onReady: { callbackReady = true }, onFailure: { callbackError = $0 })
        try #require(await eventually { callbackReady || callbackError != nil })
        #expect(callbackError == nil)
        #expect(runtime.state == .ready)
        #expect(runtime.logText.isEmpty)

        runtime.stop()
        #expect(runtime.state == .stopped)
        // Stopping an attached runtime does not touch the external service.
        try await service.checkConnection(configuration: configuration)
    }

    @Test
    @MainActor
    func cancelledStartupCannotPublishAnOldReadyCallback() async throws {
        let runtime = LocalModelRuntimeManager(translator: LocalTranslationService(session: LocalTranslationTestSession.make()))
        let configuration = LocalTranslationConfiguration(baseURLString: "http://127.0.0.1:8081/v1", modelID: "test-model")
        var callbackCount = 0
        runtime.startIfNeeded(configuration: configuration, onReady: { callbackCount += 1 }, onFailure: { _ in callbackCount += 1 })
        runtime.cancelPreparation()
        try await Task.sleep(for: .milliseconds(100))
        #expect(runtime.state == .stopped)
        #expect(callbackCount == 0)
    }

    @Test
    @MainActor
    func explicitPreparationStreamsLogsAndCancellationTerminatesItsOwnedChild() async throws {
        let fixture = try preparationFixture()
        defer { fixture.runtime.stop(); try? FileManager.default.removeItem(at: fixture.directory) }
        let task = Task { try await fixture.runtime.prepare(configuration: configuration(model: "slow-model")) }
        try #require(await eventually { fixture.runtime.logText.contains("owned-pid=") })
        #expect(fixture.runtime.state == .preparing)
        let pidLine = try #require(fixture.runtime.logText.split(separator: "\n").first { $0.hasPrefix("owned-pid=") })
        let pid = try #require(Int32(pidLine.dropFirst("owned-pid=".count)))

        fixture.runtime.cancelPreparation()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.runtime.state == .stopped)
        #expect(await eventually { Darwin.kill(pid, 0) == -1 && errno == ESRCH })
    }

    @Test
    @MainActor
    func aNewPreparationSupersedesTheOldModelWithoutStaleFailure() async throws {
        let fixture = try preparationFixture()
        defer { fixture.runtime.stop(); try? FileManager.default.removeItem(at: fixture.directory) }
        let first = Task { try await fixture.runtime.prepare(configuration: configuration(model: "slow-model")) }
        try #require(await eventually { fixture.runtime.logText.contains("owned-pid=") })
        try await fixture.runtime.prepare(configuration: configuration(model: "new-model"), downloadModel: false)
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(fixture.runtime.state == .stopped)
        #expect(fixture.runtime.logText.contains("prepared-new-model"))
        #expect(!fixture.runtime.logText.contains("owned-pid="))
    }

    @Test
    @MainActor
    func cancellationReapsOwnedGrandchildrenEvenAfterTheirLeaderExits() async throws {
        let fixture = try preparationFixture()
        defer { fixture.runtime.stop(); try? FileManager.default.removeItem(at: fixture.directory) }
        let task = Task { try await fixture.runtime.prepare(configuration: configuration(model: "stubborn-model")) }
        try #require(await eventually { fixture.runtime.logText.contains("grandchild-pid=") })
        let pidLine = try #require(fixture.runtime.logText.split(separator: "\n").first { $0.hasPrefix("grandchild-pid=") })
        let pid = try #require(Int32(pidLine.dropFirst("grandchild-pid=".count)))
        fixture.runtime.cancelPreparation()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await eventually(timeout: 12) { Darwin.kill(pid, 0) == -1 && errno == ESRCH })
        #expect(fixture.runtime.state == .stopped)
    }

    @MainActor
    private func preparationFixture() throws -> (runtime: LocalModelRuntimeManager, directory: URL) {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [project.appendingPathComponent(".venv/bin/python")]
            + LocalModelRuntimeLocator.bootstrapPythonCandidates(environment: ProcessInfo.processInfo.environment)
        let python = try #require(candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("prepare.sh")
        try """
        #!/bin/bash
        case "$*" in
          *stubborn-model*)
            /bin/sh -c 'trap "" TERM; echo "grandchild-pid=$$"; while :; do /bin/sleep 1; done' &
            wait ;;
          *slow-model*) echo "owned-pid=$$"; exec /bin/sleep 30 ;;
          *) echo prepared-new-model ;;
        esac
        """.write(to: script, atomically: true, encoding: .utf8)
        var environment = ProcessInfo.processInfo.environment
        environment["AIRTRANSLATE_LOCAL_PYTHON"] = python.path
        let runtime = LocalModelRuntimeManager(environment: environment, currentDirectoryURL: directory,
                                               homeDirectoryURL: directory, setupScriptURL: script,
                                               watchdogScriptURL: project.appendingPathComponent("Resources/local_mlx_watchdog.py"))
        return (runtime, directory)
    }

    private func configuration(model: String) -> LocalTranslationConfiguration {
        LocalTranslationConfiguration(baseURLString: LocalTranslationConfiguration.defaultBaseURLString, modelID: model)
    }

    @MainActor
    private func eventually(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}
