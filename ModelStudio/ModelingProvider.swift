import Foundation

enum ModelingProvider: String, CaseIterable {
    case codex = "Codex"
    case claude = "Claude"
    case antigravity = "Antigravity"

    var models: [String] {
        switch self {
        case .codex: ["gpt-6.2-sol", "gpt-6.2-astra"]
        case .claude: ["sonnet", "opus"]
        case .antigravity: ["gemini-4-hydrogen", "gemini-3.8-flash"]
        }
    }

    var credentialName: String {
        switch self {
        case .codex: "CODEX_API_KEY"
        case .claude: "ANTHROPIC_API_KEY"
        case .antigravity: "GEMINI_API_KEY"
        }
    }

    fileprivate func command(model: String) -> [String] {
        switch self {
        case .codex:
            ["codex", "exec", "--model", model, "--ephemeral", "--skip-git-repo-check",
             "--sandbox", "read-only", "--ignore-user-config", "--ignore-rules",
             "--disable", "shell_tool", "--disable", "computer_use", "--disable", "multi_agent",
             "--disable", "plugins", "--disable", "hooks", "-c", "web_search=\"disabled\"", "-"]
        case .claude:
            ["claude", "--print", "--model", model, "--bare", "--tools", "",
             "--no-session-persistence", "--disable-slash-commands", "--strict-mcp-config",
             "--mcp-config", "{\"mcpServers\":{}}", "--output-format", "text"]
        case .antigravity:
            ["python", "/opt/studio/agent.py", model]
        }
    }

    static let preferencesKey = "modeling.provider"
    var modelKey: String { "modeling.model." + rawValue }
}

struct ProviderRoute {
    let provider: ModelingProvider
    let model: String

    init(defaults: UserDefaults = .standard) {
        let provider = defaults.string(forKey: ModelingProvider.preferencesKey)
            .flatMap(ModelingProvider.init(rawValue:)) ?? .codex
        self.provider = provider
        let saved = defaults.string(forKey: provider.modelKey)
        model = saved.flatMap { provider.models.contains($0) ? $0 : nil } ?? provider.models[0]
    }

    var arguments: [String] {
        ["run", "--rm", "--interactive", "--init", "--pull=never", "--read-only",
         "--user", "1000:1000", "--cap-drop=ALL", "--security-opt=no-new-privileges",
         "--log-driver=none", "--tmpfs", "/tmp:rw,exec,nosuid,nodev,size=256m,mode=1777",
         "--env", "HOME=/tmp", "--env", provider.credentialName,
         "--workdir", "/studio", "--entrypoint", "/usr/bin/timeout",
         "modelstudio-" + provider.rawValue.lowercased() + ":1", "-k", "5", "180"]
            + provider.command(model: model)
    }

    func send(_ input: ModelingInput, transport: ProviderTransport = DockerTransport()) async throws -> ModelingReply {
        let header = """
        You are the background modeling agent in 3D Model Studio. Use the indexed surface below.
        Coordinates are XYZ triples in the supplied unit. targetFaceIDs is the authorized selection.
        readOnlyFaceIDs are context only. Return exactly one JSON object without Markdown.
        For an edit return {"kind":"proposal","message":"description","patch":{"vertices":[],"faces":[],"removedFaceIDs":[]}}.
        List only new or changed items. Vertices have id and position; triangular faces have id and vertices.
        Preserve existing IDs; assign negative temporary IDs to new items. For creation propose the initial mesh.
        For a selection edit you may instead request specific additional faces by ID or faces across a supplied
        boundary edge: {"kind":"access","message":"specific reason","faceIDs":[],"acrossEdges":[[a,b]]}.
        For a question or unsupported constraint return {"kind":"explanation","message":"question or explanation"}.
        """
        var payload = Data((header + "\n").utf8)
        payload.append(try JSONEncoder().encode(input))
        return try await ModelingReply(data: transport.run(route: self, input: payload))
    }
}

protocol ProviderTransport {
    func run(route: ProviderRoute, input: Data) async throws -> Data
}

struct DockerTransport: ProviderTransport {
    // Unlinked descriptors carry the payload across exec without a pipe buffer
    // deadlock or a named host file the provider could open.
    private func scratchFile(in directory: URL) throws -> FileHandle {
        var template = Array(directory.appendingPathComponent("stream.XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else { throw MeshImportError("Could not prepare the provider stream.") }
        unlink(template)
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    func run(route: ProviderRoute, input: Data) async throws -> Data {
        let fm = FileManager.default
        let binaries = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker",
                        "/Applications/Docker.app/Contents/Resources/bin/docker"]
        guard let binary = binaries.first(where: fm.isExecutableFile(atPath:)) else {
            throw MeshImportError("Install Docker and prepare the provider image as described in Providers/README.md.")
        }
        let sockets = [fm.homeDirectoryForCurrentUser.appendingPathComponent(".docker/run/docker.sock").path,
                       "/var/run/docker.sock"]
        guard let socket = sockets.first(where: fm.fileExists(atPath:)) else {
            throw MeshImportError("Start the local Docker engine before sending a modeling request.")
        }
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: dir) }
        let stdin = try scratchFile(in: dir)
        let stdout = try scratchFile(in: dir)
        try stdin.write(contentsOf: input)
        try stdin.seek(toOffset: 0)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--config", dir.path, "--host", "unix://" + socket] + route.arguments
        // Docker forwards only the named key. No user Docker configuration, proxy
        // settings, host directories, sockets or prior session are passed inside.
        process.environment = ProcessInfo.processInfo.environment.filter { $0.key == route.provider.credentialName }
        process.currentDirectoryURL = dir
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try Task.checkCancellation()
        try process.run()
        let deadline = ContinuousClock.now.advanced(by: .seconds(200))
        defer { if process.isRunning { process.terminate() } }
        while process.isRunning {
            guard ContinuousClock.now < deadline else { throw MeshImportError("The provider timed out.") }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard process.terminationStatus == 0 else {
            throw MeshImportError("\(route.provider.rawValue) exited with status \(process.terminationStatus). Check the local image, \(route.provider.credentialName), and model access.")
        }
        let limit = 16 * 1024 * 1024
        try stdout.seek(toOffset: 0)
        let result = try stdout.read(upToCount: limit + 1) ?? Data()
        guard result.count <= limit else { throw MeshImportError("The provider reply exceeded 16 MiB.") }
        return result
    }
}
