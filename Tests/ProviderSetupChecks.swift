private final class FixtureKeys: ProviderCredentials {
    var keys: [ModelingProvider: String] = [:]
    var refuseWrite = false

    func read(_ provider: ModelingProvider) throws -> String? { keys[provider] }
    func save(_ key: String, for provider: ModelingProvider) throws {
        if refuseWrite { throw MeshImportError("Fixture Keychain denied access.") }
        keys[provider] = key
    }
    func remove(_ provider: ModelingProvider) throws { keys[provider] = nil }
}

@MainActor
private func exerciseSetup(_ defaults: UserDefaults) async throws {
    let fm = FileManager.default
    let directory = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    let resources = directory.appendingPathComponent("resources")
    try fm.createDirectory(at: resources, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: directory) }
    let privateFile = directory.appendingPathComponent("other-model.obj")
    try Data("undisclosed model".utf8).write(to: privateFile)
    let root = directory.appendingPathComponent("Application Support/Providers")
    let installer = resources.appendingPathComponent("install.sh")
    let runtime = NativeRuntime(root: root, resources: resources, installer: installer)
    try fm.copyItem(at: URL(fileURLWithPath: "Providers/Runtime/turn.sb"), to: resources.appendingPathComponent("turn.sb"))
    let binary = #"""
    #!/bin/bash
    set -eu
    [[ "$PWD" == "$HOME" && "$HOME" == "$TMPDIR" ]] || exit 21
    [[ -z "${STUDIO_TEST_INHERIT:-}" && ! -f "$HOME/old-turn" ]] || exit 22
    touch "$HOME/old-turn"
    if /bin/cat 'PRIVATE_FILE' >/dev/null 2>&1; then exit 23; fi
    case "$1" in
      exec) provider=Codex; key=$CODEX_API_KEY; model=$3
            [[ -z "${ANTHROPIC_API_KEY:-}${GEMINI_API_KEY:-}" ]] ;;
      --print) provider=Claude; key=$ANTHROPIC_API_KEY; model=$3
               [[ -z "${CODEX_API_KEY:-}${GEMINI_API_KEY:-}" ]] ;;
      -I) provider=Antigravity; key=$GEMINI_API_KEY; model=$3
          [[ -r "$2" && ${2##*/} == antigravity.py && -z "${CODEX_API_KEY:-}${ANTHROPIC_API_KEY:-}" ]] ;;
      *) exit 24 ;;
    esac
    [[ "$key" == "fixture-$provider" ]] || exit 25
    input=$(/bin/cat)
    case "$input" in
      "Reply with exactly this text and nothing else: STUDIO-"*) echo "${input##* }" ;;
      *"Move the selected corner upward"*)
        [[ "$input" != *918273* && "$input" != *"Confidential import"* && "$input" == *'"targetFaceIDs":[0]'* ]]
        echo "{\"kind\":\"explanation\",\"message\":\"$provider used $model\"}" ;;
      *) echo -n "$input" ;;
    esac
    """#.replacingOccurrences(of: "PRIVATE_FILE", with: privateFile.path)
    try Data(binary.utf8).write(to: resources.appendingPathComponent("double"))
    let script = #"""
    set -eu
    [[ -z "${STUDIO_TEST_INHERIT:-}${CODEX_API_KEY:-}${ANTHROPIC_API_KEY:-}${GEMINI_API_KEY:-}" ]]
    if [[ -f "$2/fail" ]]; then exit 11; fi
    case "$1" in
      Codex) binary=native/bin/codex; mkdir -p native/bin ;;
      Claude) binary=claude ;;
      Antigravity) binary=python/bin/python3; mkdir -p python/bin; touch antigravity.py ;;
    esac
    cp "$2/double" "$binary"
    chmod 700 "$binary"
    """#
    try Data(script.utf8).write(to: installer)
    let credentials = FixtureKeys()
    let connections = NativeProviders(runtime: runtime, credentials: credentials)
    setenv("STUDIO_TEST_INHERIT", "private", 1)
    defer { unsetenv("STUDIO_TEST_INHERIT") }
    let fail = resources.appendingPathComponent("fail")
    for provider in ModelingProvider.allCases {
        defaults.set(provider.rawValue, forKey: ModelingProvider.preferencesKey)
        defaults.set(provider.models.last!, forKey: provider.modelKey)
        let route = ProviderRoute(defaults: defaults)
        func checkStatus(_ expected: String) {
            precondition(connections.status(provider).contains(expected), connections.status(provider))
            precondition(!connections.busy.contains(provider))
        }
        connections.refresh(provider)
        checkStatus("Runtime required")
        await connections.connect(route, enteredKey: "")
        checkStatus("Enter a")
        try Data().write(to: fail)
        let key = "fixture-" + provider.rawValue
        await connections.connect(route, enteredKey: key)
        checkStatus("Download failed")
        precondition(runtime.installed(provider) == nil && credentials.keys[provider] == nil)
        try fm.removeItem(at: fail)
        await connections.connect(route, enteredKey: "invalid")
        checkStatus("Check your API key")
        precondition(runtime.installed(provider) != nil && credentials.keys[provider] == nil)
        credentials.refuseWrite = true
        await connections.connect(route, enteredKey: key)
        checkStatus("Keychain denied")
        credentials.refuseWrite = false
        await connections.connect(route, enteredKey: key)
        checkStatus("Connected to " + provider.rawValue + " · " + route.model)
        await connections.connect(route, enteredKey: "invalid")
        checkStatus("Check your API key")
        precondition(credentials.keys[provider] == key)
        try Data().write(to: fail)
        await connections.connect(route, enteredKey: "", reinstall: true)
        checkStatus("Download failed")
        precondition(runtime.installed(provider) != nil)
        try fm.removeItem(at: fail)
        await connections.connect(route, enteredKey: "", reinstall: true)
        checkStatus("Connected to")
        let reopened = NativeProviders(runtime: runtime, credentials: credentials)
        reopened.refresh(provider)
        precondition(reopened.status(provider).contains("Key saved"))
        let payload = Data(repeating: 65, count: 300_000)
        let echoed = try await reopened.run(route: route, input: payload)
        precondition(echoed == payload)
        for model in provider.models {
            defaults.set(model, forKey: provider.modelKey)
            let session = ModelingSession(transport: reopened)
            session.start(scope: .selection(try fixture(), [0]), instruction: "Move the selected corner upward", defaults: defaults)
            try await settle(session)
            precondition(session.message == "\(provider.rawValue) used \(model)", session.message)
        }
        reopened.disconnect(provider)
        precondition(credentials.keys[provider] == nil)
        do {
            _ = try await reopened.run(route: route, input: payload)
            preconditionFailure("Disconnected provider ran")
        } catch { precondition(error.localizedDescription.contains("Open Settings")) }
        print("\(provider.rawValue): native provisioning, authentication, retry, repair, reconnect, selected-model routing, sandbox isolation and disconnect passed.")
    }
}
try await exerciseSetup(defaults)
