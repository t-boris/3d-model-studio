import Foundation

private let explanation = #"{"kind":"explanation","message":"Completed fixture request."}"#
private let ask = #"{"kind":"access","message":"Check the surface across the shared edge.","acrossEdges":[[1,0]]}"#
private let proposal = #"{"kind":"proposal","message":"Move the corner.","patch":{"vertices":[{"id":2,"position":[0,2,0]}],"faces":[],"removedFaceIDs":[]}}"#

private struct Capture {
    let provider: ModelingProvider
    let model: String
    let arguments: [String]
    let json: [String: Any]
    let raw: String

    func ids(_ key: String) -> [Int] {
        (json[key] as! [[String: Any]]).map { $0["id"] as! Int }.sorted()
    }
}

private actor Recorder: ProviderTransport {
    var replies: [String] = []
    var captured: [Capture] = []

    func respond(_ replies: [String]) { self.replies = replies }

    func run(route: ProviderRoute, input: Data) async throws -> Data {
        let raw = String(decoding: input, as: UTF8.self)
        let json = try JSONSerialization.jsonObject(with: Data(raw.split(separator: "\n").last!.utf8)) as! [String: Any]
        captured.append(Capture(provider: route.provider, model: route.model, arguments: route.arguments,
                                json: json, raw: raw))
        precondition(!replies.isEmpty, "Unexpected provider request")
        return Data(replies.removeFirst().utf8)
    }
}

@MainActor
private func settle(_ session: ModelingSession) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while session.busy {
        precondition(ContinuousClock.now < deadline)
        try await Task.sleep(for: .milliseconds(1))
    }
}

private func fixture() throws -> WorkspaceModel {
    var mesh = EditableMesh()
    mesh.vertices = [[0,0,0], [1,0,0], [0,1,0], [7.125,0,0], [918273,0,0], [0,813579,0], [0,0,741258], [987654,0,0]]
    mesh.addFace(0,1,2)
    mesh.addFace(1,0,3)
    mesh.addFace(4,5,6)
    return try WorkspaceModel(name: "Confidential import.obj", unit: .inch, mesh: mesh)
}

@MainActor
private func exercise(_ provider: ModelingProvider, defaults: UserDefaults) async throws {
    defaults.set(provider.rawValue, forKey: ModelingProvider.preferencesKey)
    defaults.set(provider.models.last!, forKey: provider.modelKey)
    let model = try fixture()
    let recorder = Recorder()
    let session = ModelingSession(transport: recorder)
    let instruction = "Move the selected corner one inch"

    for scope in [ModelingScope.creation(draft: nil), .creation(draft: model), .revision(model)] {
        let create = #"{"kind":"proposal","message":"Create a triangle.","patch":{"vertices":[{"id":-1,"position":[0,2,0]},{"id":-2,"position":[0,0,0]},{"id":-3,"position":[1,0,0]}],"faces":[{"id":-1,"vertices":[-1,-2,-3]}],"removedFaceIDs":[],"requestedDimensions":[],"unsupportedConstraints":[]}}"#
        let revise = #"{"kind":"proposal","message":"Move the corner.","patch":{"vertices":[{"id":2,"position":[0,2,0]}],"faces":[],"removedFaceIDs":[],"requestedDimensions":[],"unsupportedConstraints":[]}}"#
        await recorder.respond([scope.model == nil ? create : revise])
        session.start(scope: scope, instruction: instruction, defaults: defaults)
        try await settle(session)
        precondition(session.patch?.vertices.first?.position == [0,2,0])
        let call = await recorder.captured.last!
        precondition(call.provider == provider && call.model == provider.models.last!)
        precondition(call.json["instruction"] as? String == instruction)
        precondition(call.json["operation"] as? String == scope.title)
        precondition(call.ids("faces") == (scope.model == nil ? [] : [0,1,2]))
        precondition(call.ids("vertices") == (scope.model == nil ? [] : Array(0...6)))
        precondition(call.json["unit"] as? String == (scope.model == nil ? "millimeter" : "inch"))
        precondition(!call.raw.contains("987654") && !call.raw.contains(model.name))
        precondition(call.arguments.contains("--read-only") && call.arguments.contains("--rm"))
        precondition(!call.arguments.contains("--mount") && !call.arguments.contains("-v"))
        precondition(call.arguments.contains("modelstudio-" + provider.rawValue.lowercased() + ":1"))
        precondition(call.arguments.contains(provider.credentialName))
        switch provider {
        case .codex:
            precondition(call.arguments.suffix(1) == ["-"])
            precondition(call.arguments.contains("exec") && call.arguments.contains("--ephemeral"))
        case .claude:
            precondition(call.arguments.contains("--print") && call.arguments.contains("--strict-mcp-config"))
            precondition(call.arguments[call.arguments.firstIndex(of: "--tools")! + 1].isEmpty)
        case .antigravity:
            precondition(Array(call.arguments.suffix(3)) == ["python", "/opt/studio/agent.py", call.model])
        }
        if provider != .antigravity { precondition(call.arguments[call.arguments.firstIndex(of: "--model")! + 1] == call.model) }
    }

    let scope = ModelingScope.selection(model, [0])
    await recorder.respond([ask, proposal])
    session.start(scope: scope, instruction: instruction, defaults: defaults)
    try await settle(session)
    let initial = await recorder.captured.last!
    precondition(initial.ids("faces") == [0] && initial.ids("vertices") == [0,1,2])
    precondition(initial.json["boundaryEdges"] as? [[Int]] == [[0,1],[0,2],[1,2]])
    precondition(initial.json["readOnlyFaceIDs"] as? [Int] == [])
    precondition(!initial.raw.contains("7.125") && !initial.raw.contains("918273"))
    let review = session.review!
    precondition(review.faceIDs == [1] && review.reason.contains("shared edge"))
    session.answer(UUID(), allow: true)
    precondition(session.review?.id == review.id)
    defaults.set("invalid model", forKey: provider.modelKey)
    session.answer(review.id, allow: true)
    try await settle(session)
    let approved = await recorder.captured.last!
    precondition(approved.model == provider.models.last!)
    precondition(approved.ids("faces") == [0,1] && approved.ids("vertices") == [0,1,2,3])
    precondition(approved.json["readOnlyFaceIDs"] as? [Int] == [1])
    precondition(approved.json["targetFaceIDs"] as? [Int] == [0])
    precondition(approved.raw.contains("7.125") && !approved.raw.contains("918273"))
    precondition(session.review == nil && session.patch != nil)

    await recorder.respond([ask])
    session.start(scope: scope, instruction: instruction, defaults: defaults)
    try await settle(session)
    let fresh = await recorder.captured.last!
    precondition(fresh.model == provider.models.first!)
    precondition(fresh.ids("faces") == [0] && !fresh.raw.contains("7.125"))
    session.answer(review.id, allow: true)
    let denied = session.review!
    precondition(denied.id != review.id)
    let before = await recorder.captured.count
    session.answer(denied.id, allow: false)
    precondition(session.review == nil && session.message.contains(denied.reason) && session.patch == nil)
    session.answer(denied.id, allow: true)
    let after = await recorder.captured.count
    precondition(after == before)

    await recorder.respond([ask])
    session.start(scope: scope, instruction: instruction, defaults: defaults)
    try await settle(session)
    let canceled = session.review!
    session.cancel()
    session.answer(canceled.id, allow: true)
    precondition(session.review == nil && !session.busy)
    let count = await recorder.captured.count
    precondition(count == after + 1)

    for bad in [#"{"kind":"access","message":"inspect","faceIDs":[999]}"#,
                #"{"kind":"access","message":"inspect","acrossEdges":[[0,3]]}"#,
                #"{"kind":"access","message":" ","faceIDs":[2]}"#, "unstructured text"] {
        await recorder.respond([bad])
        session.start(scope: scope, instruction: instruction, defaults: defaults)
        try await settle(session)
        precondition(session.review == nil && session.patch == nil && !session.message.isEmpty)
    }
    let invalidCount = await recorder.captured.count
    session.start(scope: .selection(model, [987]), instruction: instruction, defaults: defaults)
    try await settle(session)
    let finalCount = await recorder.captured.count
    precondition(finalCount == invalidCount)

    let operation = ModelingOperation(scope: .selection(model, [0,1]), instruction: instruction)
    let multi = try operation.input()
    precondition(!multi.boundaryEdges.contains([0,1]) && multi.faces.count == 2)
    try operation.request(faceIDs: [2], acrossEdges: [], reason: "Check the other part.")
    do { _ = try operation.input(); preconditionFailure("Input escaped during review") } catch {}
    try operation.resolve(operation.review!.id, allow: true)
    let expanded = try operation.input()
    precondition(expanded.readOnlyFaceIDs == [2] && expanded.targetFaceIDs == [0,1])
    operation.end()
    do { _ = try operation.input(); preconditionFailure("Input escaped after expiry") } catch {}
    print("\(provider.rawValue): routed \(provider.models.joined(separator: ", ")); creation, revision, selection, disclosure, refusal and expiry passed")
}

let suite = "studio.provider-checks." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
for provider in ModelingProvider.allCases { try await exercise(provider, defaults: defaults) }

// Exercise Foundation Process and the anonymous streams without Docker, an
// agent, the host environment or a network connection.
private func exerciseProcess(_ defaults: UserDefaults) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let binary = directory.appendingPathComponent("fixture")
    let script = """
    #!/bin/sh
    [ "$1" = "--config" ] && [ "$2" = "$HOME" ] && [ "$3" = "--host" ] || exit 2
    [ "$4" = "unix:///fixture.sock" ] && [ "$5" = "run" ] || exit 3
    /bin/cat
    """
    try Data(script.utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
    let bytes = Data(repeating: 65, count: 300_000)
    for provider in ModelingProvider.allCases {
        defaults.set(provider.rawValue, forKey: ModelingProvider.preferencesKey)
        let route = ProviderRoute(defaults: defaults)
        let response = try await DockerTransport().invoke(route: route, input: bytes, binary: binary.path,
                                                          socket: "/fixture.sock", environment: [:])
        precondition(response == bytes)
    }
    print("Native provider subprocess transport passed for large piped requests with a local echo fixture.")
}

try await exerciseProcess(defaults)

// Some transports may deliver a response after cancellation. It must never
// resurrect the old operation's review in the replacement operation.
private actor SuspendedProvider: ProviderTransport {
    private var first: CheckedContinuation<Data, Never>?
    private var calls = 0

    var waiting: Bool { first != nil }

    func run(route: ProviderRoute, input: Data) async throws -> Data {
        calls += 1
        if calls == 1 { return await withCheckedContinuation { first = $0 } }
        precondition(route.provider == .claude)
        return Data(explanation.utf8)
    }

    func deliverLate() {
        first?.resume(returning: Data(ask.utf8))
        first = nil
    }
}

@MainActor
private func replaceInFlight(_ defaults: UserDefaults) async throws {
    let transport = SuspendedProvider()
    let session = ModelingSession(transport: transport)
    let model = try fixture()
    defaults.set(ModelingProvider.codex.rawValue, forKey: ModelingProvider.preferencesKey)
    session.start(scope: .selection(model, [0]), instruction: "First operation", defaults: defaults)
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !(await transport.waiting) {
        precondition(ContinuousClock.now < deadline)
        try await Task.sleep(for: .milliseconds(1))
    }
    defaults.set(ModelingProvider.claude.rawValue, forKey: ModelingProvider.preferencesKey)
    session.start(scope: .selection(model, [2]), instruction: "Replacement", defaults: defaults)
    try await settle(session)
    await transport.deliverLate()
    try await Task.sleep(for: .milliseconds(10))
    precondition(session.review == nil && session.message == "Completed fixture request.")
    print("Changing provider starts a fresh operation; late replies cannot revive a closed access review.")
}

try await replaceInFlight(defaults)
