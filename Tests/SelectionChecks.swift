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
    await recorder.respond([reply])
    let ambiguous = "Make it 31 mm overall"
    session.start(scope: .selection(workspace.activeModel!, [selected]), instruction: ambiguous, defaults: defaults)
    precondition(session.question?.contains(ambiguous) == true && session.proposal == nil)
    precondition(!session.apply(to: workspace, confirmedProposal: first.id))
    session.clarify("final span along Z is 31 mm")
    try await settle(session)
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
    await recorder.respond([reply])
    session.start(scope: .selection(workspace.activeModel!, [selected]), instruction: "Raise it by 2 mm", defaults: defaults)
    precondition(session.question != nil)
    session.clarify("final span along Z is \(height) mm")
    try await settle(session)
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
    precondition(detached.impact?.outside == [1,2] && detached.impact?.removed == [0])
    precondition(detached.impact?.originalFaces == [0,1,2] && detached.impact?.candidateFaces == [1,2])
    let scoped = ModelingOperation(scope: .selection(original, [0,1,2]), instruction: "Remove the first face")
    let scopedRemoval = try ModelingProposal(operation: scoped, patch: AgentMeshPatch(vertices: [], faces: [],
                                              removedFaceIDs: [0], requestedDimensions: [], unsupportedConstraints: []))
    precondition(!scopedRemoval.requiresConfirmation && scopedRemoval.impact?.originalFaces == [0,1,2])
    precondition(scopedRemoval.impact?.candidateFaces == [1,2])
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
    precondition(island.impact?.outside == [3] && island.requiresConfirmation)
    precondition(island.impact?.originalFaces == [] && island.impact?.candidateFaces == [3])
    print("Connectivity-only changes, edge winding, vertex-only incidence, removals and additions passed.")
}

@MainActor
private func exerciseAssemblySelection(_ provider: ModelingProvider, file: String) async throws {
    let workspace = Workspace()
    await workspace.open(URL(fileURLWithPath: "Fixtures/Import/Assemblies/" + file))
    let model = workspace.activeModel!
    let mesh = model.mesh
    let assembly = mesh.assembly!
    let selected = mesh.faces.first { assembly.occurrences[1].contains(faceID: $0.id) }!
    let sibling = mesh.faces.first { assembly.occurrences[0].contains(faceID: $0.id) }!
    let withheld = mesh.faces.first { $0.id != sibling.id && assembly.occurrences[0].contains(faceID: $0.id) }!
    let v = selected.vertices
    let edge = [v.x, v.y].sorted()
    let across = mesh.faces.filter { face in
        let corners = [face.vertices.x, face.vertices.y, face.vertices.z]
        return face.id != selected.id && edge.allSatisfy(corners.contains)
    }
    precondition(across.count == 1 && assembly.occurrences[1].contains(faceID: across[0].id))

    let recorder = Recorder()
    let session = ModelingSession(transport: recorder)
    defaults.set(provider.rawValue, forKey: ModelingProvider.preferencesKey)
    let instruction = "Subdivide the selected triangle"
    let reason = "Compare the adjoining triangle and the indicated face on the sibling for alignment."
    let access = try JSONSerialization.data(withJSONObject: ["kind": "access", "message": reason,
                                                               "faceIDs": [sibling.id], "acrossEdges": [edge]])
    let request = String(decoding: access, as: UTF8.self)
    let more = #"{"kind":"access","message":"Compare another sibling face.","faceIDs":["# + String(withheld.id) + "]}"
    let a = mesh.vertices[v.x], b = mesh.vertices[v.y], c = mesh.vertices[v.z]
    func subdivide(at position: SIMD3<Double>) throws -> String {
        try wire(AgentMeshPatch(vertices: [.init(id: -1, position: position)],
                                faces: [.init(id: -1, vertices: [v.x,v.y,-1]), .init(id: -2, vertices: [v.y,v.z,-1]),
                                        .init(id: -3, vertices: [v.z,v.x,-1])], removedFaceIDs: [selected.id],
                                requestedDimensions: [], unsupportedConstraints: []))
    }
    func checkInput(sharing additional: [MeshFace]) async {
        let input = await recorder.captured.last!
        let visible = [selected] + additional
        let vertices = Set(visible.flatMap { [$0.vertices.x, $0.vertices.y, $0.vertices.z] })
        precondition(input.provider == provider && input.ids("faces") == visible.map(\.id).sorted())
        precondition(input.ids("vertices") == vertices.sorted() && !input.raw.contains(model.name))
        precondition(input.json["targetFaceIDs"] as? [Int] == [selected.id])
        precondition(input.json["readOnlyFaceIDs"] as? [Int] == additional.map(\.id).sorted())
        precondition(input.json["boundaryEdges"] as? [[Int]] == [[v.x,v.y], [v.y,v.z], [v.z,v.x]].map { $0.sorted() }
            .sorted { $0.lexicographicallyPrecedes($1) })
        precondition(input.json["assembly"] == nil && input.json["parts"] == nil)
    }
    func start(replies: [String]) async throws {
        await recorder.respond(replies)
        session.start(scope: .selection(workspace.activeModel!, [selected.id]), instruction: instruction, defaults: defaults)
        try await settle(session)
        await checkInput(sharing: [])
    }

    try await start(replies: [request, more])
    let review = session.review!
    precondition(review.reason == reason && review.faceIDs == [sibling.id, across[0].id])
    precondition(review.parts.map(\.faceIDs) == [[sibling.id], [across[0].id]])
    let labels = file == "repeated-block.3mf" ? ["Build item 1 · Component 1 › 1", "Build item 1 · Component 2 › 1"]
        : ["Build item 1 · Component 1", "Build item 2 · Component 1"]
    precondition(review.parts.compactMap(\.label) == labels)
    session.answer(review.id, allow: true)
    try await settle(session)
    await checkInput(sharing: [sibling, across[0]])
    let denied = session.review!
    let sentBeforeDecline = await recorder.captured.count
    session.answer(denied.id, allow: false)
    session.answer(denied.id, allow: true)
    let sentAfterDecline = await recorder.captured.count
    precondition(sentBeforeDecline == sentAfterDecline && session.message.contains(denied.reason))
    precondition(session.proposal == nil && workspace.activeModel!.mesh == mesh)

    try await start(replies: [request, try subdivide(at: (a + b + c) / 3)])
    let fresh = session.review!
    session.answer(review.id, allow: true)
    precondition(session.review?.id == fresh.id)
    session.answer(fresh.id, allow: true)
    try await settle(session)
    let rejected = session.proposal!
    precondition(rejected.requiresConfirmation && !session.apply(to: workspace, confirmedProposal: fresh.id))
    session.discard()
    precondition(workspace.activeModel!.mesh == mesh)

    try await start(replies: [try subdivide(at: (a + a + b + c) / 4)])
    let candidate = session.proposal!
    let impact = candidate.impact!
    let added = Set(mesh.nextFaceID..<(mesh.nextFaceID + 3))
    precondition(impact.removed == [selected.id] && impact.added == added && impact.outside.isSuperset(of: added))
    precondition(impact.outside.contains(across[0].id) && !impact.outside.contains(sibling.id))
    precondition(candidate.preview.mesh != rejected.preview.mesh)
    precondition(!session.apply(to: workspace, confirmedProposal: rejected.id) && workspace.activeModel!.mesh == mesh)

    let viewport = ModelViewport.Coordinator()
    for (surface, affected) in [(mesh, impact.originalFaces), (candidate.preview.mesh, impact.candidateFaces)] {
        let outside = affected.intersection(impact.outside)
        let inside = affected.subtracting(outside)
        viewport.update(mesh: surface, selection: outside, point: nil, affectedSelection: inside)
        precondition(Set(viewport.faceGroups[1].map { surface.faces[$0].id }) == outside)
        if !inside.isEmpty {
            precondition(Set(viewport.faceGroups[2].map { surface.faces[$0].id }) == [selected.id])
        }
    }
    precondition(session.apply(to: workspace, confirmedProposal: candidate.id))
    let edited = workspace.activeModel!.mesh
    let occurrence = edited.assembly!.occurrences[1]
    precondition(added.allSatisfy(occurrence.contains(faceID:)))
    precondition(mesh.faces.filter { !occurrence.contains(faceID: $0.id) } == edited.faces.filter { !occurrence.contains(faceID: $0.id) })
    precondition(edited.vertices.dropLast() == mesh.vertices[...])
    let next = ModelingOperation(scope: .selection(workspace.activeModel!, [withheld.id]), instruction: "Inspect a new face")
    try next.request(faceIDs: [added.min()!], acrossEdges: [], reason: "Identify the previously edited occurrence.")
    precondition(next.review?.parts.first?.label == labels[1])
    viewport.update(mesh: edited, selection: [], point: nil)
    precondition(viewport.displayed == candidate.preview.mesh)
    print("\(provider.rawValue) · \(file): occurrence labels, exact disclosure, refusal, removed/added review and commit passed")
}

try selectionTopologyChecks()
for provider in ModelingProvider.allCases {
    for source: String? in [nil, "stl", "obj", "3mf"] { try await exerciseSelectedEdits(provider, source: source) }
    for file in ["bambu-blocks.3mf", "orca-blocks.3mf", "repeated-block.3mf"] {
        try await exerciseAssemblySelection(provider, file: file)
    }
}
