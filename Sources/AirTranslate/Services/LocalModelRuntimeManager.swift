import Foundation
import Observation

enum LocalModelRuntimeState: Equatable, Sendable {
    case stopped
    case preparing
    case starting
    case ready
    case failed(String)
}

struct LocalModelRuntimeLocator {
    static let verifiedMLXLMVersion = "0.31.3"

    static func runtimeDirectory(homeDirectoryURL: URL) -> URL {
        homeDirectoryURL.appendingPathComponent("Library/Application Support/AirTranslate/LocalMLX", isDirectory: true)
    }
    static func pythonCandidates(
        bundleURL: URL,
        currentDirectoryURL: URL,
        homeDirectoryURL: URL,
        environment: [String: String]
    ) -> [URL] {
        var candidates = [URL]()

        if let override = environment["AIRTRANSLATE_LOCAL_PYTHON"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }

        let standardDirectory = environment["AIRTRANSLATE_LOCAL_RUNTIME_DIR"].map { URL(fileURLWithPath: $0) }
            ?? runtimeDirectory(homeDirectoryURL: homeDirectoryURL)
        candidates.append(standardDirectory.appendingPathComponent(".venv/bin/python"))

        if bundleURL.pathExtension.lowercased() == "app" {
            let projectRoot = bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            candidates.append(projectRoot.appendingPathComponent(".venv/bin/python"))
        }

        candidates.append(currentDirectoryURL.appendingPathComponent(".venv/bin/python"))

        var seen = Set<String>()
        return candidates.filter { candidate in
            seen.insert(candidate.standardizedFileURL.path).inserted
        }
    }

    static func resolvePythonExecutable(
        bundleURL: URL = Bundle.main.bundleURL,
        currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        pythonCandidates(
            bundleURL: bundleURL,
            currentDirectoryURL: currentDirectoryURL,
            homeDirectoryURL: homeDirectoryURL,
            environment: environment
        ).first { candidate in
            fileManager.isExecutableFile(atPath: candidate.path)
        }
    }

    static func watchdogCandidates(bundleURL: URL, pythonURL: URL) -> [URL] {
        resourceCandidates(name: "local_mlx_watchdog.py", bundleURL: bundleURL, pythonURL: pythonURL)
    }

    static func resourceCandidates(name: String, bundleURL: URL, pythonURL: URL) -> [URL] {
        var candidates = [URL]()
        if let resourceURL = Bundle(url: bundleURL)?.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(name))
        } else if bundleURL.pathExtension.lowercased() == "app" {
            candidates.append(
                bundleURL
                    .appendingPathComponent("Contents/Resources", isDirectory: true)
                    .appendingPathComponent(name)
            )
        }
        candidates.append(
            pythonURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/" + name)
        )
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/" + name))
        return candidates
    }

    static func bootstrapPythonCandidates(environment: [String: String]) -> [URL] {
        var paths = [String]()
        if let override = environment["AIRTRANSLATE_BOOTSTRAP_PYTHON"], !override.isEmpty { paths.append(override) }
        paths += ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        paths += (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/python3" }
        // This system stub may launch the Xcode installer on a fresh Mac.
        return paths.filter { $0 != "/usr/bin/python3" }.map { URL(fileURLWithPath: $0) }
    }

    static func resolveWatchdogScript(
        bundleURL: URL = Bundle.main.bundleURL,
        pythonURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        watchdogCandidates(bundleURL: bundleURL, pythonURL: pythonURL).first { candidate in
            fileManager.isReadableFile(atPath: candidate.path)
        }
    }
}

private final class LocalRuntimeOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        pending.append(data)
        if pending.count > 65_536 { pending = Data(pending.suffix(65_536)) }
    }

    func drain() -> String {
        lock.lock()
        defer { lock.unlock() }
        let text = String(decoding: pending, as: UTF8.self)
        pending.removeAll(keepingCapacity: true)
        return text
    }
}

@MainActor
@Observable
final class LocalModelRuntimeManager {
    private(set) var state = LocalModelRuntimeState.stopped
    private(set) var logText = ""

    @ObservationIgnored private let translator: LocalTranslationService
    @ObservationIgnored private let environment: [String: String]
    @ObservationIgnored private let bundleURL: URL
    @ObservationIgnored private let currentDirectoryURL: URL
    @ObservationIgnored private let homeDirectoryURL: URL
    @ObservationIgnored private let setupScriptOverride: URL?
    @ObservationIgnored private let watchdogScriptOverride: URL?
    @ObservationIgnored private let readinessTimeout: TimeInterval
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private var preparationTask: Task<Void, Error>?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var output: LocalRuntimeOutput?
    @ObservationIgnored private var retiringProcesses = [Process]()
    @ObservationIgnored private var operationGeneration = UUID()
    @ObservationIgnored private var failureHandler: (@MainActor (String) -> Void)?

    init(
        translator: LocalTranslationService = LocalTranslationService(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleURL: URL = Bundle.main.bundleURL,
        currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        setupScriptURL: URL? = nil,
        watchdogScriptURL: URL? = nil,
        readinessTimeout: TimeInterval = 300
    ) {
        self.translator = translator
        self.environment = environment
        self.bundleURL = bundleURL
        self.currentDirectoryURL = currentDirectoryURL
        self.homeDirectoryURL = homeDirectoryURL
        self.setupScriptOverride = setupScriptURL
        self.watchdogScriptOverride = watchdogScriptURL
        self.readinessTimeout = readinessTimeout
    }

    /// This path is offline: packages and model weights are never downloaded.
    func startIfNeeded(
        configuration: LocalTranslationConfiguration,
        onReady: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        let generation = beginOperation()
        failureHandler = onFailure
        state = .starting
        startupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try LocalTranslationService.endpoint(baseURLString: configuration.trimmedBaseURLString, relativePath: "models")
                try await waitForRetiringProcesses(generation: generation)
                if await isServiceReady(configuration: configuration) {
                    try validateOperation(generation)
                    state = .ready
                    startupTask = nil
                    onReady()
                    return
                }
                try validateOperation(generation)
                guard let python = resolvedRuntimePython() else { throw LocalModelRuntimeError.runtimeNotFound }
                try await runSetup(configuration: configuration, python: python, checkOnly: true,
                                   downloadModel: false, generation: generation)
                try launchServer(configuration: configuration, python: python)
                let deadline = Date().addingTimeInterval(readinessTimeout)
                while Date() < deadline {
                    try validateOperation(generation)
                    collectOutput()
                    guard process?.isRunning == true else { throw LocalModelRuntimeError.serverExited }
                    if await isServiceReady(configuration: configuration) {
                        try validateOperation(generation)
                        _ = try await translator.translate("Hello.", source: .english, target: .chineseSimplified,
                                                           configuration: configuration)
                        try validateOperation(generation)
                        state = .ready
                        startupTask = nil
                        startMonitoring(generation: generation)
                        onReady()
                        return
                    }
                    try await Task.sleep(for: .milliseconds(250))
                }
                throw LocalModelRuntimeError.readinessTimedOut
            } catch {
                guard operationGeneration == generation else { return }
                startupTask = nil
                if error is CancellationError { return }
                collectOutput()
                stopOwnedProcess()
                let message = error.localizedDescription
                state = .failed(message)
                failureHandler = nil
                onFailure(message)
            }
        }
    }

    /// Explicit installation/download. It may take minutes; cancellation stops
    /// only commands owned by this manager. Success leaves the runtime stopped.
    func prepare(configuration: LocalTranslationConfiguration, downloadModel: Bool = true) async throws {
        let generation = beginOperation()
        state = .preparing
        let task = Task { @MainActor in
            _ = try LocalTranslationService.endpoint(baseURLString: configuration.trimmedBaseURLString, relativePath: "models")
            guard !configuration.trimmedModelID.isEmpty else { throw LocalTranslationError.emptyModelID }
            try await waitForRetiringProcesses(generation: generation)
            let python = resolvedRuntimePython() ?? LocalModelRuntimeLocator.bootstrapPythonCandidates(environment: environment)
                .first { FileManager.default.isExecutableFile(atPath: $0.path) }
            guard let python else { throw LocalModelRuntimeError.pythonNotFound }
            try await runSetup(configuration: configuration, python: python, checkOnly: false,
                               downloadModel: downloadModel, generation: generation)
            try validateOperation(generation)
        }
        preparationTask = task
        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try validateOperation(generation)
            preparationTask = nil
            state = .stopped
        } catch {
            guard operationGeneration == generation else { throw CancellationError() }
            collectOutput()
            stopOwnedProcess()
            preparationTask = nil
            state = error is CancellationError ? .stopped : .failed(error.localizedDescription)
            throw error
        }
    }

    func cancelPreparation() { stop() }

    func stop() {
        operationGeneration = UUID()
        startupTask?.cancel()
        startupTask = nil
        preparationTask?.cancel()
        preparationTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        failureHandler = nil
        collectOutput()
        stopOwnedProcess()
        state = .stopped
    }

    private func beginOperation() -> UUID {
        stop()
        logText = ""
        return operationGeneration
    }

    private func validateOperation(_ generation: UUID) throws {
        try Task.checkCancellation()
        guard generation == operationGeneration else { throw CancellationError() }
    }

    private func resolvedRuntimePython() -> URL? {
        LocalModelRuntimeLocator.resolvePythonExecutable(bundleURL: bundleURL, currentDirectoryURL: currentDirectoryURL,
                                                        homeDirectoryURL: homeDirectoryURL, environment: environment)
    }

    private func resource(_ name: String, python: URL) throws -> URL {
        let override = name == "setup_local_mlx.sh" ? setupScriptOverride : watchdogScriptOverride
        let candidates = override.map { [$0] } ?? LocalModelRuntimeLocator.resourceCandidates(name: name, bundleURL: bundleURL, pythonURL: python)
        guard let url = candidates.first(where: { FileManager.default.isReadableFile(atPath: $0.path) }) else {
            throw LocalModelRuntimeError.resourceNotFound(name)
        }
        return url
    }

    private func runSetup(configuration: LocalTranslationConfiguration, python: URL,
                          checkOnly: Bool, downloadModel: Bool, generation: UUID) async throws {
        let setup = try resource("setup_local_mlx.sh", python: python)
        let directory = environment["AIRTRANSLATE_LOCAL_RUNTIME_DIR"].map { URL(fileURLWithPath: $0) }
            ?? LocalModelRuntimeLocator.runtimeDirectory(homeDirectoryURL: homeDirectoryURL)
        var args = ["/bin/bash", setup.path, "--runtime-dir", directory.path, "--model", configuration.trimmedModelID]
        if let installedPython = resolvedRuntimePython() { args += ["--python", installedPython.path] }
        if checkOnly { args.append("--check") }
        if downloadModel { args.append("--download-model") }
        let command = try launchOwnedCommand(args, python: python, offline: checkOnly)
        while command.isRunning {
            try validateOperation(generation)
            collectOutput()
            try await Task.sleep(for: .milliseconds(100))
        }
        try validateOperation(generation)
        collectOutput()
        process = nil
        output = nil
        switch command.terminationStatus {
        case 0: break
        case 10: throw LocalModelRuntimeError.runtimeNotFound
        case 11: throw LocalModelRuntimeError.pythonNotFound
        case 12: throw LocalModelRuntimeError.unsupportedHardware
        case 13: throw LocalModelRuntimeError.modelNotPrepared
        default: throw LocalModelRuntimeError.setupFailed
        }
    }

    private func launchServer(configuration: LocalTranslationConfiguration, python: URL) throws {
        let endpoint = try LocalTranslationService.endpoint(baseURLString: configuration.trimmedBaseURLString, relativePath: "models")
        guard let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme == "http", components.path == "/v1/models",
              let port = components.port, (1024...65_535).contains(port), let host = components.host
        else { throw LocalModelRuntimeError.unsupportedConfiguration }
        _ = try launchOwnedCommand([
            python.path, "-m", "mlx_lm", "server", "--model", configuration.trimmedModelID,
            "--host", host.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: ""),
            "--port", String(port), "--log-level", "CRITICAL"
        ], python: python, offline: true)
    }

    @discardableResult
    private func launchOwnedCommand(_ command: [String], python: URL, offline: Bool) throws -> Process {
        let watchdog = try resource("local_mlx_watchdog.py", python: python)
        let child = Process()
        child.executableURL = python
        child.arguments = [watchdog.path, String(ProcessInfo.processInfo.processIdentifier)] + command
        child.currentDirectoryURL = currentDirectoryURL
        var childEnvironment = environment
        childEnvironment["HF_HUB_DISABLE_XET"] = childEnvironment["HF_HUB_DISABLE_XET"] ?? "1"
        childEnvironment["PYTHONUNBUFFERED"] = "1"
        if offline {
            childEnvironment["HF_HUB_OFFLINE"] = "1"
            childEnvironment["TRANSFORMERS_OFFLINE"] = "1"
        }
        child.environment = childEnvironment
        let pipe = Pipe()
        let buffer = LocalRuntimeOutput()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            else { buffer.append(data) }
        }
        child.standardOutput = pipe
        child.standardError = pipe
        try child.run()
        process = child
        output = buffer
        return child
    }

    private func collectOutput() {
        guard let text = output?.drain(), !text.isEmpty else { return }
        logText = String((logText + text).suffix(20_000))
    }

    private func stopOwnedProcess() {
        if let process, process.isRunning {
            process.terminate()
            retiringProcesses.append(process)
        }
        process = nil
        output = nil
    }

    private func waitForRetiringProcesses(generation: UUID) async throws {
        let deadline = Date().addingTimeInterval(15)
        while retiringProcesses.contains(where: \.isRunning) {
            try validateOperation(generation)
            guard Date() < deadline else { throw LocalModelRuntimeError.previousProcessStopping }
            try await Task.sleep(for: .milliseconds(100))
        }
        retiringProcesses.removeAll()
        try validateOperation(generation)
    }

    private func isServiceReady(configuration: LocalTranslationConfiguration) async -> Bool {
        do { try await translator.checkConnection(configuration: configuration); return true }
        catch { return false }
    }

    private func startMonitoring(generation: UUID) {
        monitorTask = Task { @MainActor [weak self] in
            while let self, generation == operationGeneration, !Task.isCancelled {
                collectOutput()
                guard let process else { return }
                if !process.isRunning {
                    let message = LocalModelRuntimeError.serverExited.localizedDescription
                    self.process = nil
                    output = nil
                    state = .failed(message)
                    failureHandler?(message)
                    failureHandler = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}

private enum LocalModelRuntimeError: LocalizedError {
    case pythonNotFound, runtimeNotFound, readinessTimedOut, unsupportedConfiguration, previousProcessStopping
    case unsupportedHardware, modelNotPrepared, setupFailed, serverExited
    case resourceNotFound(String)

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            LocalUI.text("请先从 python.org 安装 Apple 芯片版 Python 3.11 或更新版本，再准备模型。", "Install Python 3.11 or newer for Apple Silicon from python.org, then prepare the model.")
        case .runtimeNotFound:
            LocalUI.text("本地环境尚未安装，请点击准备模型。", "The local environment is not installed. Choose Prepare Model.")
        case .modelNotPrepared:
            LocalUI.text("所选模型尚未完整下载，请点击准备模型。", "The selected model is not fully downloaded. Choose Prepare Model.")
        case .unsupportedHardware:
            LocalUI.text("本地 MLX 模型需要 Apple 芯片 Mac。", "The local MLX model requires an Apple Silicon Mac.")
        case .readinessTimedOut:
            LocalUI.text("模型加载超时，请在设置中查看模型诊断。", "Model loading timed out. See model diagnostics in Settings.")
        case .unsupportedConfiguration:
            LocalUI.text("自动启动需要本机 HTTP 地址、/v1 路径和 1024–65535 端口。", "Automatic startup needs a loopback HTTP address, the /v1 path, and port 1024–65535.")
        case .previousProcessStopping:
            LocalUI.text("上一个模型进程正在停止，请稍后重试。", "The previous model process is still stopping. Retry shortly.")
        case .resourceNotFound(let name):
            LocalUI.text("缺少应用资源 \(name)，请重新安装完整应用。", "Missing app resource \(name). Reinstall the complete app.")
        case .setupFailed:
            LocalUI.text("模型准备失败，请在设置中查看模型诊断。", "Model preparation failed. See model diagnostics in Settings.")
        case .serverExited:
            LocalUI.text("模型进程已退出，请在设置中查看模型诊断。", "The model process exited. See model diagnostics in Settings.")
        }
    }
}
