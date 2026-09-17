import Foundation
import Testing
@testable import AirTranslate

@Suite
struct LocalMLXScriptTests {
    @Test
    func aHalfCreatedVirtualEnvironmentRestoresPipWithoutNetworkAccess() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = directory.appendingPathComponent("managed runtime")
        let python = try bootstrapPython()
        var environment = isolatedEnvironment(directory: directory)
        environment["AIRTRANSLATE_BOOTSTRAP_PYTHON"] = python.path
        let created = try run(python, ["-m", "venv", "--without-pip", runtime.appendingPathComponent(".venv").path], environment: environment)
        try #require(created.status == 0, Comment(rawValue: created.output))
        let runtimePython = runtime.appendingPathComponent(".venv/bin/python")
        #expect(try run(runtimePython, ["-m", "pip", "--version"], environment: environment).status != 0)

        // PyPI and cache access are disabled. The real bundled ensurepip can
        // restore pip; the subsequent MLX install must fail locally without
        // downloading packages or changing the user's installed environment.
        let prepared = try run(URL(fileURLWithPath: "/bin/bash"), [setupScript.path, "--runtime-dir", runtime.path], environment: environment)
        #expect(prepared.status != 0)
        #expect(prepared.output.contains("Restoring pip in the managed virtual environment"))
        #expect(prepared.output.contains("Installing verified runtime dependency"))
        #expect(try run(runtimePython, ["-m", "pip", "--version"], environment: environment).status == 0)
    }

    @Test
    func anIncompatibleExplicitPythonOverrideFailsBeforeInstallingAnotherEnvironment() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let override = directory.appendingPathComponent("broken-python")
        try executable("#!/bin/sh\nexit 1\n", at: override)
        let runtime = directory.appendingPathComponent("must-not-be-created")
        var environment = isolatedEnvironment(directory: directory)
        environment["AIRTRANSLATE_LOCAL_PYTHON"] = override.path

        let result = try run(URL(fileURLWithPath: "/bin/bash"), [setupScript.path, "--runtime-dir", runtime.path], environment: environment)

        #expect(result.status == 14)
        #expect(result.output.contains("unset AIRTRANSLATE_LOCAL_PYTHON"))
        #expect(!FileManager.default.fileExists(atPath: runtime.path))
        #expect(!result.output.contains("Local model environment is ready"))
    }

    @Test
    func manualStartupUsesStandardRuntimeThenRepositoryAndKeepsRequestsOutOfLogs() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("project/script/start_local_mlx.sh")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: project.appendingPathComponent("script/start_local_mlx.sh"), to: script)
        let standard = directory.appendingPathComponent("standard runtime")
        let repoPython = directory.appendingPathComponent("project/.venv/bin/python")
        let standardPython = standard.appendingPathComponent(".venv/bin/python")
        try fakeServerPython(label: "repository", at: repoPython)
        try fakeServerPython(label: "standard", at: standardPython)
        var environment = isolatedEnvironment(directory: directory)
        environment["AIRTRANSLATE_LOCAL_RUNTIME_DIR"] = standard.path

        let preferred = try run(URL(fileURLWithPath: "/bin/bash"), [script.path], environment: environment)
        #expect(preferred.status == 0)
        #expect(preferred.output.contains("selected=standard"))
        #expect(preferred.output.contains("--log-level\nCRITICAL"))
        #expect(preferred.output.contains("offline=1/1"))

        try FileManager.default.removeItem(at: standardPython)
        let fallback = try run(URL(fileURLWithPath: "/bin/bash"), [script.path], environment: environment)
        #expect(fallback.status == 0)
        #expect(fallback.output.contains("selected=repository"))

        let explicit = directory.appendingPathComponent("explicit-python")
        try fakeServerPython(label: "explicit", at: explicit)
        environment["AIRTRANSLATE_LOCAL_PYTHON"] = explicit.path
        let overridden = try run(URL(fileURLWithPath: "/bin/bash"), [script.path], environment: environment)
        #expect(overridden.output.contains("selected=explicit"))
    }

    private var project: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private var setupScript: URL { project.appendingPathComponent("Resources/setup_local_mlx.sh") }

    private func bootstrapPython() throws -> URL {
        let candidates = [project.appendingPathComponent(".venv/bin/python")]
            + LocalModelRuntimeLocator.bootstrapPythonCandidates(environment: ProcessInfo.processInfo.environment)
        return try #require(candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func isolatedEnvironment(directory: URL) -> [String: String] {
        [
            "HOME": directory.path,
            "PATH": "/usr/bin:/bin",
            "PIP_CONFIG_FILE": "/dev/null",
            "PIP_NO_INDEX": "1",
            "PIP_NO_CACHE_DIR": "1",
            "PIP_DISABLE_PIP_VERSION_CHECK": "1"
        ]
    }

    private func fakeServerPython(label: String, at url: URL) throws {
        try executable("""
        #!/bin/sh
        echo selected=\(label)
        echo "offline=$HF_HUB_OFFLINE/$TRANSFORMERS_OFFLINE"
        printf '%s\\n' "$@"
        """, at: url)
    }

    private func executable(_ script: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func run(_ executable: URL, _ arguments: [String], environment: [String: String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
