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

private func creationReply(spans: SIMD3<Double> = [20, 10, 5]) throws -> String {
    let block = try WorkspaceModel.newBlock()
    let vertices = block.mesh.vertices.enumerated().map { i, v in
        ModelingInput.Vertex(id: -1 - i, position: (v / 10) * spans)
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
    let instruction = "Make this block 7 mm tall. The final span along X is 20 mm and a depth of 10 mm."
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

    let mesh = workspace.activeModel!.mesh
    let face = mesh.faces[0], v = face.vertices
    let edges = [SIMD2(v.x, v.y), SIMD2(v.y, v.z), SIMD2(v.z, v.x)].map { SIMD2(min($0.x, $0.y), max($0.x, $0.y)) }
    func reviseForPrintCheck(_ instruction: String, faces: [ModelingInput.Face] = [], removed: [Int] = []) async throws {
        let patch = AgentMeshPatch(vertices: [], faces: faces, removedFaceIDs: removed,
                                   requestedDimensions: [], unsupportedConstraints: [])
        let priorResult = workspace.printValidation.label
        try await prepare(instruction, try wire(patch))
        precondition(workspace.printValidation.label == priorResult)
        precondition(session.apply(to: workspace), session.message)
        precondition(workspace.printValidation.label == "Outdated · Run again")
        await workspace.validatePrintGeometry()
    }

    func checkEdgeIssues(_ expectedProblem: PrintGeometryReport.Problem, excluding excluded: Int? = nil) {
        guard case .current(let report) = workspace.printValidation else { fatalError("Missing revision result") }
        precondition(report.issues.count == 3 && Set(report.issues.compactMap(\.edge)) == Set(edges))
        for issue in report.issues {
            let edge = issue.edge!
            let incident = mesh.faces.filter {
                let c = [$0.vertices.x, $0.vertices.y, $0.vertices.z]
                return $0.id != excluded && c.contains(edge.x) && c.contains(edge.y)
            }
            precondition(issue.problem == expectedProblem && issue.faces == incident.map(\.id))
        }
    }

    await workspace.validatePrintGeometry()
    precondition(workspace.printValidation.label == "Pass")
    try await reviseForPrintCheck("Reverse the winding of the first face", faces: [.init(id: face.id, vertices: [v.x, v.z, v.y])])
    checkEdgeIssues(.winding)
    try await reviseForPrintCheck("Restore the original winding", faces: [.init(id: face.id, vertices: v)])
    precondition(workspace.printValidation.label == "Pass")
    try await reviseForPrintCheck("Open the surface at the first triangle", removed: [face.id])
    checkEdgeIssues(.boundary, excluding: face.id)
    try await reviseForPrintCheck("Close the triangular opening", faces: [.init(id: -1, vertices: v)])
    precondition(workspace.printValidation.label == "Pass")
    let repaired = workspace.activeModel!.mesh
    precondition(repaired.faces.dropLast().elementsEqual(mesh.faces.dropFirst()))
    precondition(repaired.faces.last?.id == mesh.nextFaceID)
    print("\(provider.rawValue) · \(source ?? "creation and clarification"): revisions, viewport, units, pins, winding and open-edge failure/repair passed")
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
        return try operation.dimensions.targets()
    }
    let spans = try targets("Make a 2x1x0.5 cm block.")
    precondition(spans == [target(.width, 2, .centimeter), target(.depth, 1, .centimeter), target(.height, 0.5, .centimeter)])
    let mixed = try targets("Make it 2 cm × 10 mm × 1/2 in.")
    precondition(mixed == [target(.width, 2, .centimeter), target(.depth, 10), target(.height, 0.5, .inch)])
    let cube = try targets("Make a 1 1/2 inch cube.")
    precondition(cube == ModelDimension.allCases.map { target($0, 1.5, .inch) })
    for text in ["Remove one of these faces", "Remove two of the selected faces", "Delete these two triangles",
                 "Delete the top 2 triangles", "Split this face into three triangles", "Subdivide each selected face into 4 triangles",
                 "Round the edges of this 3MF part", "Remove face 3", "Merge these 2 faces", "Move these 2 selected triangles"] {
        let parsed = try targets(text)
        precondition(parsed.isEmpty, text)
    }
    let inches = try targets("Set the height to 5 in.")
    precondition(inches == [target(.height, 5, .inch)])
    do { _ = try targets("Set it to 7 cm"); fatalError("Unchecked length") }
    catch { precondition(error.localizedDescription.contains("Restate")) }
    do { _ = try targets("Make it 7 mm tall with a 3 mm bore."); fatalError("Unchecked second length") }
    catch { precondition(error.localizedDescription.contains("3 mm")) }
    for text in ["height 7", "make it one inch across", "double its height", "make it at least 7 mm tall",
                 "set width to 7 mm and width to 8 mm", "make the flange width 2 cm", "set height to 1/0 in",
                 "move the selected corner one inch", "final span along Y is -3 mm", "Set the height to 5 in the new block",
                 "Move these selected faces by 2 mm", "Move one of these faces by 2 mm"] {
        do { _ = try targets(text); fatalError("Expected restatement for " + text) }
        catch { precondition(error.localizedDescription.contains("Restate"), error.localizedDescription) }
    }
    for text in ["Give it a 30 degree angle", "set the wall thickness to 2 mm", "keep the bottom at Z = 0"] {
        do { _ = try targets(text); fatalError("Unsupported constraint") }
        catch { precondition(error.localizedDescription.contains("Unsupported dimensional constraint")) }
    }
    let all = ModelingOperation(scope: .creation(draft: nil), instruction: "Use the same size in all three dimensions")
    all.clarify(question: all.dimensions.question!, answer: "final span along X is 3 mm")
    precondition(all.dimensions.question?.contains("Depth (Y)") == true)
    all.clarify(question: all.dimensions.question!, answer: "final span along Y is 3 mm and final span along Z is 3 mm")
    let three = try all.dimensions.targets()
    precondition(three == ModelDimension.allCases.map { target($0, 3) })
    let relative = ModelingOperation(scope: .creation(draft: nil), instruction: "Create a block")
    relative.clarify(question: "By how much should its height grow?", answer: "5 mm")
    precondition(relative.dimensions.question != nil)
    relative.clarify(question: relative.dimensions.question!, answer: "final span along Z is 8 mm")
    let clarified = try relative.dimensions.targets()
    precondition(clarified == [target(.height, 8)])
    print("Explicit, relative, conflicting, unsupported and invalid spans, compact dimensions and fractional inches checked.")
}

@MainActor
private func restatementChecks() async throws {
    let workspace = Workspace()
    let recorder = Recorder()
    let session = ModelingSession(transport: recorder)
    let instruction = "Create a 2 cm wide block."
    let shapeQuestion = "What shape should it have?"
    let ambiguous = "Use a box, allow 10 mm across and allow 10 mm overall."
    let restateY = "final span along Y is 1 cm"
    let restateZ = "final span along Z is 5 mm"
    let patch = try creationReply()
    guard case let .proposal(_, interpreted) = try ModelingReply(data: Data(patch.utf8)) else { fatalError() }
    let operation = ModelingOperation(scope: .creation(draft: nil), instruction: instruction)
    operation.clarify(question: shapeQuestion, answer: ambiguous)
    // This candidate satisfies even its provider-supplied dimensions exactly.
    // Direct construction must enforce the same unresolved-state guard as the UI.
    do { _ = try ModelingProposal(operation: operation, patch: interpreted); fatalError("Unbound proposal") }
    catch { precondition(error.localizedDescription.contains("10 mm across")) }

    func request(_ spans: SIMD3<Double>) async throws {
        let initialCount = await recorder.captured.count
        await recorder.respond([#"{"kind":"question","message":"What shape should it have?"}"#, try creationReply(spans: spans)])
        session.start(scope: .creation(draft: nil), instruction: instruction, defaults: defaults)
        try await settle(session)
        precondition(session.question == shapeQuestion)
        session.clarify(ambiguous)
        precondition(session.question?.contains("10 mm across") == true && session.proposal == nil)
        session.clarify(restateY)
        precondition(session.question?.contains("10 mm overall") == true && !session.apply(to: workspace))
        session.clarify("yes")
        precondition(session.question?.contains("10 mm overall") == true && workspace.activeModel == nil)
        let waitingCount = await recorder.captured.count
        precondition(waitingCount == initialCount + 1)
        session.clarify(restateZ)
        try await settle(session)
        let input = await recorder.captured.last!.json
        let answers = input["clarifications"] as! [[String: String]]
        precondition(input["instruction"] as? String == instruction)
        precondition(answers.compactMap { $0["answer"] } == [ambiguous, restateY, "yes", restateZ])
    }
    for axis in ModelDimension.allCases {
        var spans = SIMD3<Double>(20, 10, 5)
        spans[axis.axis] += 0.0101
        try await request(spans)
        precondition(session.proposal == nil && session.message.contains("Requested " + axis.label), session.message)
        precondition(workspace.activeModel == nil)
    }
    try await request([20.01, 9.99, 5.01])
    precondition(session.proposal?.requested == [target(.width, 2, .centimeter), target(.depth, 1, .centimeter), target(.height, 5)])
    precondition(session.apply(to: workspace))
    let created = workspace.activeModel!
    // A provider-only value from this reply must neither bind nor resolve a target.
    await recorder.respond([try heightReply(created, 8, dimensions: [target(.height, 99)])])
    session.start(scope: .revision(created), instruction: "Double its height", defaults: defaults)
    precondition(session.question?.contains("height") == true && session.proposal == nil)
    session.clarify("final span along Z is 8 mm")
    try await settle(session)
    precondition(session.proposal?.requested == [target(.height, 8)] && session.apply(to: workspace))

    let revised = workspace.activeModel!
    let heightQuestion = "What height should the block have?"
    await recorder.respond([#"{"kind":"question","message":"What height should the block have?"}"#,
                            try heightReply(revised, 9, dimensions: [target(.width, 20)])])
    session.start(scope: .revision(revised), instruction: "Revise the block", defaults: defaults)
    try await settle(session)
    precondition(session.question == heightQuestion)
    let beforeAnswer = await recorder.captured.count
    session.clarify("9")
    let pendingHeight = session.question
    precondition(pendingHeight?.contains("span along Z") == true)
    session.clarify("final span along X is 20 mm")
    precondition(session.question == pendingHeight && !session.apply(to: workspace))
    let stillWaiting = await recorder.captured.count
    precondition(stillWaiting == beforeAnswer && workspace.activeModel!.mesh == revised.mesh)
    session.clarify("final span along Z is 9 mm")
    try await settle(session)
    precondition(session.proposal?.requested == [target(.width, 20), target(.height, 9)])
    precondition(session.apply(to: workspace))
    precondition(workspace.activeModel!.extents.z == 9)
    print("Two equal unbound lengths, retained answers, provider-independent targets, three out-of-tolerance rejections and inclusive endpoints passed.")
}

try literalChecks()
try await restatementChecks()
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
