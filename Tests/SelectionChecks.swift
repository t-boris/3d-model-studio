import Foundation

@MainActor
private func exerciseSelectedEdits(_ provider: ModelingProvider, source: String?) async throws {
    let workspace = Workspace()
    if let source {
        await workspace.open(URL(fileURLWithPath: "Fixtures/Import/block." + source))
        if source != "3mf" { workspace.acceptUnit(.millimeter) }
    } else {
        workspace.newBlock()
    }
    let original = workspace.activeModel!
    let recorder = Recorder()
    let session = ModelingSession(transport: recorder)
    defaults.set(provider.rawValue, forKey: ModelingProvider.preferencesKey)
    let factor = original.unit.millimetersPerUnit
    let top = original.mesh.surfaceBounds.high.z
    let corner = original.mesh.vertices.firstIndex { $0.z == top }!
    let incident = Set(original.mesh.faces.filter {
        let v = $0.vertices
        return v.x == corner || v.y == corner || v.z == corner
    }.map(\.id))
    let selected = incident.min()!
    let neighbor = incident.subtracting([selected]).min()!

    func moveCorner(_ mm: Double) throws -> String {
        var p = original.mesh.vertices[corner]
        p.z = top + mm / factor
        return try wire(AgentMeshPatch(vertices: [.init(id: corner, position: p)], faces: [], removedFaceIDs: [],
                                       requestedDimensions: [], unsupportedConstraints: []))
    }

    func start(_ ids: Set<Int>, _ instruction: String, replies: [String]) async throws {
        await recorder.respond(replies)
        session.start(scope: .selection(workspace.activeModel!, ids), instruction: instruction, defaults: defaults)
        try await settle(session)
        let input = await recorder.captured.last!
        precondition(input.provider == provider && input.ids("faces") == ids.sorted())
        precondition(input.json["targetFaceIDs"] as? [Int] == ids.sorted())
        precondition(input.json["readOnlyFaceIDs"] as? [Int] == [])
    }

    let viewport = ModelViewport.Coordinator()
    viewport.update(mesh: original.mesh, selection: incident, point: nil)
    try await start(incident, "Lift the common corner", replies: [try moveCorner(1)])
    let inside = session.proposal!
    precondition(inside.impact?.affected == incident && !inside.requiresConfirmation)
    precondition(workspace.activeModel!.mesh == original.mesh)
    precondition(session.apply(to: workspace))
    let baseline = workspace.activeModel!
    precondition(baseline.mesh == inside.preview.mesh && baseline.id == original.id)
    viewport.update(mesh: baseline.mesh, selection: incident, point: nil)
    precondition(viewport.displayed != original.mesh && viewport.displayed == inside.preview.mesh)

    let access = #"{"kind":"access","message":"Inspect this incident triangle.","faceIDs":["# + String(neighbor) + "]}"
    let outside = incident.subtracting([selected])
    let reply = try moveCorner(2)
    try await start([selected], "Lift the same corner again", replies: [access, reply])
    let readID = session.review!.id
    session.answer(readID, allow: true)
    try await settle(session)
    let disclosed = await recorder.captured.last!
    precondition(disclosed.ids("faces") == [selected, neighbor].sorted())
    precondition(disclosed.json["targetFaceIDs"] as? [Int] == [selected])
    let first = session.proposal!
    precondition(first.impact?.outside == outside && first.requiresConfirmation)
    precondition(!session.apply(to: workspace) && !session.apply(to: workspace, confirmedProposal: readID))
    precondition(session.proposal?.id == first.id && workspace.activeModel!.mesh == baseline.mesh)
    for mesh in [baseline.mesh, first.preview.mesh] {
        viewport.update(mesh: mesh, selection: outside, point: nil, affectedSelection: [selected])
        precondition(viewport.surface.geometry?.elementCount == 3)
        precondition(Set(viewport.faceGroups[1].map { mesh.faces[$0].id }) == outside)
        precondition(viewport.faceGroups[2].map { mesh.faces[$0].id } == [selected])
    }
    session.discard()
    precondition(!session.apply(to: workspace, confirmedProposal: first.id))
    precondition(workspace.activeModel!.mesh == baseline.mesh && session.proposal == nil)

    // The user's length still binds when the provider omits it. Confirmation
    // must check this after the preview and preserve the workspace on failure.
    try await start([selected], "Make the height 31 mm", replies: [reply])
    let wrong = session.proposal!
    precondition(!session.apply(to: workspace, confirmedProposal: first.id))
    precondition(session.proposal?.id == wrong.id && wrong.impact?.outside == outside)
    precondition(!session.apply(to: workspace, confirmedProposal: wrong.id))
    precondition(session.message.contains("Requested Height (Z)") && workspace.activeModel!.mesh == baseline.mesh)
    try await start([selected], "Lift the same corner again", replies: [reply])
    let pendingID = session.proposal!.id
    for axis in ModelDimension.allCases { workspace.pinCurrent(axis) }
    let pins = workspace.activeModel!.pins
    precondition(!session.apply(to: workspace, confirmedProposal: pendingID))
    precondition(session.message.contains("Pinned Height (Z)") && workspace.activeModel!.mesh == baseline.mesh)
    precondition(workspace.activeModel!.pins == pins)

    workspace.unpin(.height)
    let height = original.extents.z * factor + 2
    try await start([selected], "Make the height \(height) mm", replies: [reply])
    let confirmed = session.proposal!
    precondition(session.apply(to: workspace, confirmedProposal: confirmed.id))
    let applied = workspace.activeModel!
    precondition(applied.mesh == confirmed.preview.mesh && applied.id == baseline.id && applied.pins.count == 2)
    viewport.update(mesh: applied.mesh, selection: [selected], point: nil)
    precondition(viewport.displayed == applied.mesh && abs(applied.extents.z * factor - height) < 1e-9)
    print("\(provider.rawValue) · \(source ?? "new block"): selected edits, scoped disclosure, outside highlights, decline, confirmation and dimension conflicts passed")
}

private func selectionTopologyChecks() throws {
    var mesh = EditableMesh()
    mesh.vertices = [[0,0,0], [1,0,0], [0,1,0], [1,1,0], [-1,0,0], [0,-1,0]]
    mesh.addFace(0,1,2) // Selected
    mesh.addFace(2,1,3) // Shared edge
    mesh.addFace(0,4,5) // Only a shared vertex
    let original = try WorkspaceModel(name: "Patch", unit: .millimeter, mesh: mesh)
    let op = ModelingOperation(scope: .selection(original, [0]), instruction: "Remesh this triangle")
    func proposal(_ vertices: [ModelingInput.Vertex] = [], _ faces: [ModelingInput.Face] = [],
                  removed: [Int] = []) throws -> ModelingProposal {
        try ModelingProposal(operation: op, patch: AgentMeshPatch(vertices: vertices, faces: faces,
                             removedFaceIDs: removed, requestedDimensions: [], unsupportedConstraints: []))
    }

    // Split the point at the very same coordinates. Only the vertex neighbor
    // loses incidence, while the common edge on the other side stays intact.
    let split = try proposal([.init(id: -1, position: mesh.vertices[0])], [.init(id: 0, vertices: [-1,1,2])])
    precondition(split.impact?.outside == [2])
    let reversed = try proposal([], [.init(id: 0, vertices: [0,2,1])])
    precondition(reversed.impact?.outside == [1])
    do { _ = try proposal([], [.init(id: 0, vertices: [1,2,0])]); fatalError("Cyclic no-op") }
    catch { precondition(error.localizedDescription.contains("no surface change")) }

    let detached = try proposal(removed: [0])
    precondition(detached.impact?.outside == [1,2])
    do { _ = try proposal(removed: [1]); fatalError("Undisclosed face") }
    catch { precondition(error.localizedDescription.contains("unknown")) }
    try op.request(faceIDs: [1], acrossEdges: [], reason: "Inspect the shared edge")
    try op.resolve(op.review!.id, allow: true)
    let removed = try proposal(removed: [1])
    precondition(removed.impact?.outside == [1] && removed.original!.mesh.faces.contains { $0.id == 1 })
    precondition(!removed.preview.mesh.faces.contains { $0.id == 1 })
    let added = try proposal([.init(id: -1, position: [0,0,1])], [.init(id: -1, vertices: [1,2,-1])])
    precondition(added.impact?.outside == [1,3] && added.preview.mesh.faces.last?.id == 3)
    let island = try proposal([.init(id: -1, position: [9,0,0]), .init(id: -2, position: [9,1,0]),
                               .init(id: -3, position: [9,1,1])], [.init(id: -1, vertices: [-1,-2,-3])])
    precondition(island.impact?.outside == [3])
    print("Connectivity-only changes, edge winding, vertex-only incidence, removals and additions passed.")
}

try selectionTopologyChecks()
for provider in ModelingProvider.allCases {
    for source: String? in [nil, "stl", "obj", "3mf"] { try await exerciseSelectedEdits(provider, source: source) }
}
