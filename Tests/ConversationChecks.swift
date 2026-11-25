import Foundation

private func target(_ dimension: ModelDimension, _ value: Double, _ unit: MeshUnit = .millimeter) -> DimensionTarget {
    DimensionTarget(dimension: dimension, value: value, unit: unit)
}

private func wire(_ patch: AgentMeshPatch) throws -> String {
    struct Reply: Encodable {
        let kind = "proposal"
        let message = "Proposed block edit."
        let patch: AgentMeshPatch
    }
    return String(decoding: try JSONEncoder().encode(Reply(patch: patch)), as: UTF8.self)
}

private func creationReply() throws -> String {
    let block = try WorkspaceModel.newBlock()
    let vertices = block.mesh.vertices.enumerated().map { i, v in
        ModelingInput.Vertex(id: -1 - i, position: v * [2, 1, 0.5])
    }
    let faces = block.mesh.faces.map { f in
        ModelingInput.Face(id: -1 - f.id, vertices: SIMD3(repeating: -1) &- f.vertices)
    }
    return try wire(AgentMeshPatch(vertices: vertices, faces: faces, removedFaceIDs: [],
                                   requestedDimensions: [target(.width, 2, .centimeter), target(.depth, 10),
                                                         target(.height, 5)], unsupportedConstraints: []))
}

private func heightReply(_ model: WorkspaceModel, _ heightMM: Double, dimensions: [DimensionTarget],
                         unsupported: [String] = []) throws -> String {
    let high = model.mesh.surfaceBounds.high.z
    let vertices = model.mesh.vertices.enumerated().compactMap { i, v -> ModelingInput.Vertex? in
        guard v.z == high else { return nil }
        return ModelingInput.Vertex(id: i, position: [v.x, v.y, heightMM / model.unit.millimetersPerUnit])
    }
    return try wire(AgentMeshPatch(vertices: vertices, faces: [], removedFaceIDs: [],
                                   requestedDimensions: dimensions, unsupportedConstraints: unsupported))
}

@MainActor
private func exerciseConversation(_ provider: ModelingProvider, source: String?) async throws {
    let workspace = Workspace()
    let transport = Recorder()
    let session = ModelingSession(transport: transport)
    defaults.set(provider.rawValue, forKey: ModelingProvider.preferencesKey)
    defaults.set(provider.models.last!, forKey: provider.modelKey)
    if let source {
        await workspace.open(URL(fileURLWithPath: "Fixtures/Import/block." + source))
        if source != "3mf" { workspace.acceptUnit(.millimeter) }
    } else {
        await transport.respond([#"{"kind":"question","message":"What height should the block have?"}"#,
                                 try creationReply()])
        let description = "Create a block 2 cm wide and 10 mm deep."
        session.start(scope: .creation(draft: nil), instruction: description, defaults: defaults)
        try await settle(session)
        precondition(session.question != nil && workspace.activeModel == nil)
        defaults.set(provider.models.first!, forKey: provider.modelKey)
        session.clarify("5 mm")
        try await settle(session)
        let calls = await transport.captured
        precondition(calls.count == 2 && calls.allSatisfy { $0.provider == provider && $0.model == provider.models.last! })
        let answer = calls[1].json["clarifications"] as! [[String: String]]
        precondition(answer == [["question": "What height should the block have?", "answer": "5 mm"]])
        precondition(calls[1].json["instruction"] as? String == description)
        precondition(workspace.activeModel == nil && session.proposal?.preview.mesh.faces.count == 12)
        session.apply(to: workspace)
        precondition(session.appliedTurns.count == 1 && workspace.activeModel!.pins.isEmpty)
    }
    await workspace.validatePrintGeometry()
    precondition(workspace.printValidation.label == "Pass")
    let original = workspace.activeModel!
    let factor = original.unit.millimetersPerUnit
    let viewport = ModelViewport.Coordinator()
    viewport.update(mesh: original.mesh, selection: [], point: nil)
    let initialPositions = viewport.positions.map { $0.y }
    let instruction = "Make this block 7 mm tall. Keep the bottom at Z = 0 and keep the width and depth."
    let reply = try heightReply(original, 7, dimensions: [target(.height, 7), target(.width, 20), target(.depth, 10)])
    await transport.respond([reply])
    session.start(scope: .revision(original), instruction: instruction, defaults: defaults)
    try await settle(session)
    let call = await transport.captured.last!
    precondition(call.provider == provider && call.ids("faces") == original.mesh.faces.map(\.id))
    precondition(call.json["unit"] as? String == original.unit.rawValue)
    precondition(call.json["operation"] as? String == "Revise Model")
    let previous = call.json["appliedTurns"] as! [[String: Any]]
    precondition(previous.count == (source == nil ? 1 : 0))
    if source == nil { precondition(call.model == provider.models.first!) }
    precondition(session.proposal != nil && workspace.activeModel!.mesh == original.mesh, session.message)
    session.apply(to: workspace)
    guard case .stale = workspace.printValidation else { fatalError("Applied provider edit kept old result") }
    await workspace.validatePrintGeometry()
    precondition(workspace.printValidation.label == "Pass")
    let revised = workspace.activeModel!
    precondition(revised.id == original.id && revised.mesh.faces == original.mesh.faces)
    precondition(simd_length(revised.extents * factor - [20, 10, 7]) < 1e-10 && revised.mesh.surfaceBounds.low.z == 0)
    viewport.update(mesh: revised.mesh, selection: [], point: nil)
    precondition(viewport.displayed == revised.mesh && viewport.positions.map { $0.y } != initialPositions)

    func prepare(_ text: String, _ reply: String) async throws {
        await transport.respond([reply])
        session.start(scope: .revision(workspace.activeModel!), instruction: text, defaults: defaults)
        try await settle(session)
    }
    let next = try heightReply(revised, 9, dimensions: [target(.height, 0.9, .centimeter)])
    try await prepare("Make it 0.9 cm tall", next)
    precondition(session.proposal != nil, session.message)
    workspace.pinCurrent(.height) // Pin changes while a proposal is under review.
    session.apply(to: workspace)
    precondition(session.message.contains("Pinned Height") && workspace.activeModel!.mesh == revised.mesh)
    let pins = workspace.activeModel!.pins
    try await prepare("Make it 0.9 cm tall", next)
    precondition(session.proposal == nil && session.message.contains("Pinned Height"))
    precondition(workspace.activeModel!.pins == pins)
    workspace.unpin(.height)

    // A provider that omits or contradicts the user's literal height cannot commit it.
    try await prepare("Set height to 9 mm", try heightReply(revised, 10, dimensions: []))
    precondition(session.proposal == nil && session.message.contains("Requested Height"))
    try await prepare("Give it a 2 mm radius", try heightReply(revised, 9, dimensions: []))
    precondition(session.proposal == nil && session.message.contains("Unsupported dimensional constraint"))
    try await prepare("Make a thread", try heightReply(revised, 9, dimensions: [], unsupported: ["Thread pitch"]))
    precondition(session.proposal == nil && session.message.contains("Thread pitch"))
    try await prepare("Add a slope", #"{"kind":"unsupported","message":"Slope angle cannot be measured."}"#)
    precondition(session.proposal == nil && session.message.contains("Slope angle"))
    try await prepare("Change it", "malformed")
    precondition(session.proposal == nil && session.message.contains("invalid modeling reply"))
    try await prepare("Move a corner", proposal)
    precondition(session.proposal == nil && session.message.contains("omitted its dimensional assessment"))
    precondition(workspace.activeModel!.mesh == revised.mesh)
    try await prepare("Make it 0.9 cm tall", next)
    session.discard()
    precondition(workspace.activeModel!.mesh == revised.mesh && session.proposal == nil)
    try await prepare("Make it 0.9 cm tall", next)
    session.apply(to: workspace)
    precondition(abs(workspace.activeModel!.extents.z * factor - 9) < 1e-10)
    print("\(provider.rawValue) · \(source ?? "creation and clarification"): revisions, viewport, units, pins and rejection passed")
}

for provider in ModelingProvider.allCases {
    for source: String? in [nil, "stl", "obj", "3mf"] { try await exerciseConversation(provider, source: source) }
}

@MainActor
private func proposalChecks() async throws {
    let workspace = Workspace()
    workspace.newBlock()
    let model = workspace.activeModel!
    let operation = ModelingOperation(scope: .revision(model), instruction: "Revise the surface")
    func edit(_ vertices: [ModelingInput.Vertex] = [], faces: [ModelingInput.Face] = [],
              remove: [Int] = []) throws -> ModelingProposal {
        try ModelingProposal(operation: operation, patch: AgentMeshPatch(vertices: vertices, faces: faces,
                            removedFaceIDs: remove, requestedDimensions: [], unsupportedConstraints: []))
    }
    func rejected(_ expected: String, _ action: () throws -> Void) {
        do { try action(); fatalError("Expected rejection: \(expected)") }
        catch { precondition(error.localizedDescription.contains(expected), error.localizedDescription) }
    }
    let new = ModelingInput.Vertex(id: -99, position: [5, 5, -1])
    rejected("repeats a vertex") { _ = try edit([new, new]) }
    rejected("Unknown vertex") { _ = try edit([.init(id: 8, position: [0, 0, 0])]) }
    rejected("unknown vertex") { _ = try edit(faces: [.init(id: -2, vertices: [0, 1, -99])]) }
    rejected("incident face") { _ = try edit([new]) }
    rejected("repeated face") { _ = try edit(remove: [0, 0]) }
    rejected("conflicting") { _ = try edit(faces: [.init(id: 0, vertices: [0, 1, 2])], remove: [0]) }
    rejected("collapses face") { _ = try edit(faces: [.init(id: 0, vertices: [0, 0, 1])]) }
    rejected("no surface change") { _ = try edit() }

    let remeshed = try edit([new], faces: [.init(id: 1, vertices: [0, -99, 2]),
                                          .init(id: -1, vertices: [1, -99, 2])], remove: [0])
    precondition(remeshed.preview.mesh.faces.last?.id == 12 && remeshed.preview.mesh.faces.first?.id == 1)
    precondition(remeshed.preview.mesh.vertices.count == 9 && workspace.activeModel!.mesh == model.mesh)
    try remeshed.apply(to: workspace)
    rejected("model changed") { try remeshed.apply(to: workspace) }
    let after = workspace.activeModel!
    rejected("workspace changed") { try workspace.commitCreation(model.mesh, unit: .millimeter, requested: []) }
    precondition(workspace.activeModel!.id == after.id && workspace.activeModel!.mesh == after.mesh)
    print("Malformed patches, stable topology IDs, stale revisions and stale creations checked.")
}

private func literalChecks() throws {
    func targets(_ text: String) throws -> [DimensionTarget] {
        let operation = ModelingOperation(scope: .creation(draft: nil), instruction: text)
        return try ConversationDimensions.targets(input: operation.input(), interpreted: [])
    }
    let spans = try targets("Make a 2x1x0.5 cm block.")
    precondition(spans == [target(.width, 2, .centimeter), target(.depth, 1, .centimeter), target(.height, 0.5, .centimeter)])
    let mixed = try targets("Make it 2 cm × 10 mm × 1/2 in.")
    precondition(mixed == [target(.width, 2, .centimeter), target(.depth, 10), target(.height, 0.5, .inch)])
    let cube = try targets("Make a 1 1/2 inch cube.")
    precondition(cube == ModelDimension.allCases.map { target($0, 1.5, .inch) })
    do { _ = try targets("Set it to 7 cm"); fatalError("Unchecked length") }
    catch { precondition(error.localizedDescription.contains("checkable span")) }
    do { _ = try targets("Make it 7 mm tall with a 3 mm bore."); fatalError("Unchecked second length") }
    catch { precondition(error.localizedDescription.contains("3 mm")) }
    print("Explicit spans, compact dimensions, fractional inches and unassigned lengths checked.")
}

try literalChecks()
try await proposalChecks()

private struct FailingTransport: ProviderTransport {
    func run(route: ProviderRoute, input: Data) async throws -> Data {
        throw MeshImportError("\(route.provider.rawValue) service unavailable.")
    }
}

@MainActor
private func serviceFailure() async throws {
    let workspace = Workspace()
    workspace.newBlock()
    let model = workspace.activeModel!
    let session = ModelingSession(transport: FailingTransport())
    session.start(scope: .revision(model), instruction: "Make the block taller.", defaults: defaults)
    try await settle(session)
    session.apply(to: workspace)
    precondition(session.message.contains("service unavailable") && session.proposal == nil)
    precondition(workspace.activeModel!.id == model.id && workspace.activeModel!.mesh == model.mesh)
    print("Provider transport failure reported with original geometry intact.")
}

try await serviceFailure()
