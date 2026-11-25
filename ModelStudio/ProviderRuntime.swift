import Foundation

struct ProviderInstallation {
    let directory: URL
    let executable: URL
}

struct NativeRuntime {
    let root: URL
    let resources: URL
    let installer: URL

    init(root: URL? = nil, resources: URL? = nil, installer: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.root = root ?? support.appendingPathComponent("3D Model Studio/Providers")
        self.resources = resources ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Runtime")
        self.installer = installer ?? self.resources.appendingPathComponent("install.sh")
    }

    private var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    // Change the generation when any bundled runtime input changes.
    private func directory(_ provider: ModelingProvider) -> URL {
        root.appendingPathComponent("\(provider.rawValue)-1-\(architecture)")
    }

    private func installation(_ provider: ModelingProvider, in directory: URL) -> ProviderInstallation? {
        let binary: String
        switch provider {
        case .codex: binary = "native/bin/codex"
        case .claude: binary = "claude"
        case .antigravity:
            binary = "python/bin/python3"
            guard FileManager.default.isReadableFile(atPath: directory.appendingPathComponent("antigravity.py").path)
            else { return nil }
        }
        let url = directory.appendingPathComponent(binary)
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return ProviderInstallation(directory: directory, executable: url)
    }

    func installed(_ provider: ModelingProvider) -> ProviderInstallation? {
        installation(provider, in: directory(provider))
    }

    func provision(_ provider: ModelingProvider, reinstall: Bool) async throws -> ProviderInstallation {
        if !reinstall, let existing = installed(provider) { return existing }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staging = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [installer.path, provider.rawValue, resources.path, architecture]
        process.currentDirectoryURL = staging
        process.environment = ["HOME": staging.path, "PATH": "/usr/bin:/bin", "TMPDIR": staging.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        try Task.checkCancellation()
        switch status {
        case 0: break
        case 10: throw MeshImportError("This Mac’s processor is unsupported.")
        case 11: throw MeshImportError("Download failed. Check the internet connection and retry.")
        case 12: throw MeshImportError("The runtime download failed its integrity check. Retry the download.")
        case 13: throw MeshImportError("Could not install the Python dependencies. Check the connection and disk space, then retry.")
        default: throw MeshImportError("Could not prepare \(provider.rawValue). Check free disk space and retry installation.")
        }
        guard installation(provider, in: staging) != nil else { throw MeshImportError("The runtime is incomplete. Retry installation.") }
        let target = directory(provider)
        if fm.fileExists(atPath: target.path) {
            _ = try fm.replaceItemAt(target, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: target)
        }
        guard let result = installed(provider) else { throw MeshImportError("The installed runtime is missing. Retry installation.") }
        return result
    }
}

struct ProviderProcess {
    let profile: URL

    // Unlinked files handle large inputs and replies without blocking on pipe buffers.
    private func stream(in directory: URL) throws -> FileHandle {
        var template = Array(directory.appendingPathComponent("stream.XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else { throw MeshImportError("Could not prepare the provider stream.") }
        unlink(template)
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    // Foundation can present /var even after resolving symlinks. Seatbelt
    // matches the kernel path (e.g. /private/var) for its subpath rules.
    private func sandboxPath(_ url: URL) throws -> String {
        guard let path = realpath(url.path, nil) else { throw MeshImportError("The runtime directory is unavailable. Retry installation.") }
        defer { free(path) }
        return String(cString: path)
    }

    func invoke(_ installation: ProviderInstallation, route: ProviderRoute, key: String, input: Data) async throws -> Data {
        let fm = FileManager.default
        let turn = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: turn, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: turn) }
        let stdin = try stream(in: turn)
        let stdout = try stream(in: turn)
        try stdin.write(contentsOf: input)
        try stdin.seek(toOffset: 0)

        let arguments = route.arguments(in: installation.directory)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        let turnPath = try sandboxPath(turn)
        let runtimePath = try sandboxPath(installation.directory)
        process.arguments = ["-D", "TURN=" + turnPath, "-D", "RUNTIME=" + runtimePath,
                             "-f", profile.path, installation.executable.path] + arguments
        process.currentDirectoryURL = turn
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": turnPath, "TMPDIR": turnPath,
                               "CODEX_HOME": turnPath, "CLAUDE_CONFIG_DIR": turnPath,
                               "DISABLE_AUTOUPDATER": "1", route.provider.credentialName: key]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try Task.checkCancellation()
        try process.run()
        defer {
            if process.isRunning {
                // The SDK can have a native harness child. End the turn's own
                // process group on cancellation or timeout before removing its files.
                let pid = process.processIdentifier
                if getpgid(pid) == pid { killpg(pid, SIGKILL) }
                else { kill(pid, SIGKILL) }
                process.waitUntilExit()
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(200))
        while process.isRunning {
            guard ContinuousClock.now < deadline else {
                throw MeshImportError("\(route.provider.rawValue) timed out. Check the connection and retry.")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard process.terminationStatus == 0 else {
            throw MeshImportError("\(route.provider.rawValue) could not complete the request for \(route.model) (status \(process.terminationStatus)). Check your API key, model access and network in Settings, then retry.")
        }
        let limit = 16 * 1024 * 1024
        try stdout.seek(toOffset: 0)
        let result = try stdout.read(upToCount: limit + 1) ?? Data()
        guard result.count <= limit else { throw MeshImportError("The provider reply exceeded 16 MiB.") }
        return result
    }
}
