import Foundation

private func checkPrintDefects() throws {
    let block = try WorkspaceModel.newBlock().mesh
    var flipped = block
    flipped.replaceCorners(at: 0, with: [0, 1, 2])
    let winding = PrintGeometryReport(mesh: flipped).issues
    precondition(winding.count == 3 && winding.allSatisfy { $0.problem == .winding && $0.faces.contains(0) })

    var duplicate = block
    duplicate.addFace(1, 2, 0)
    let copies = PrintGeometryReport(mesh: duplicate).issues
    precondition(copies.count == 4)
    precondition(copies.filter { $0.problem == .duplicate }.map(\.faces) == [[0, 12]])
    let crowdedEdges = copies.filter { $0.problem == .nonManifold }
    precondition(crowdedEdges.count == 3 && crowdedEdges.allSatisfy { $0.faces.count == 3 && $0.faces.contains(12) })

    var sliver = EditableMesh()
    sliver.vertices = [[0, 0, 0], [1, 0, 0], [0.5, 1e-12, 0]]
    sliver.addFace(0, 1, 2)
    for scale in [1e-200, 1.0, 1e200] {
        var triangle = sliver
        triangle.vertices = sliver.vertices.map { $0 * scale }
        precondition(PrintGeometryReport(mesh: triangle).issues.contains { $0.problem == .degenerate })
        triangle.vertices[2].y *= 2
        precondition(!PrintGeometryReport(mesh: triangle).issues.contains { $0.problem == .degenerate })
    }
    sliver.replaceCorners(at: 0, with: [2, 2, 0])
    let folded = PrintGeometryReport(mesh: sliver).issues
    precondition(folded.count == 2)
    precondition(folded.contains { $0.problem == .boundary && $0.edge == SIMD2(0, 2) && $0.faces == [0] })
    sliver.replaceCorners(at: 0, with: [2, 2, 2])
    let point = PrintGeometryReport(mesh: sliver).issues
    precondition(point.count == 1 && point[0].problem == .degenerate && point[0].markerVertex == 2)
}

// A topology-only edit can change the result even when every coordinate and dimension survives.
@MainActor
private func checkPrintInspection() async throws {
    let workspace = Workspace()
    workspace.newBlock()
    let original = workspace.activeModel!
    await workspace.validatePrintGeometry()
    var open = original.mesh
    open.removeFaces(withIDs: [0])
    try workspace.commit(open, basedOn: original)
    guard case .stale = workspace.printValidation else { fatalError("Topology change kept old result") }
    await workspace.validatePrintGeometry()
    guard case .current(let report) = workspace.printValidation else { fatalError("Missing result") }
    precondition(!report.passed && report.issues.count == 3)
    precondition(Set(report.issues.compactMap(\.edge)) == [SIMD2(0, 1), SIMD2(0, 2), SIMD2(1, 2)])
    let view = ModelViewport.Coordinator()
    for issue in report.issues {
        let edge = issue.edge!
        let expectedFaces = open.faces.filter { face in
            let v = face.vertices
            return [v.x, v.y, v.z].contains(edge.x) && [v.x, v.y, v.z].contains(edge.y)
        }
        precondition(issue.problem == .boundary && issue.faces == expectedFaces.map(\.id))
        view.update(mesh: open, selection: Set(issue.faces), point: issue.markerVertex,
                    inspectionEdge: edge, inspectingIssue: true)
        precondition(view.faceGroups.last!.map { open.faces[$0].id } == issue.faces)
        precondition(view.shownEdge == edge && view.edgeOverlay.geometry?.elements.first?.primitiveCount == 1)
        precondition(!view.marker.isHidden && view.marker.geometry?.firstMaterial?.readsFromDepthBuffer == false)
    }
    try workspace.commit(original.mesh, basedOn: workspace.activeModel!)
    guard case .stale = workspace.printValidation else { fatalError("Repair kept old failure") }
    await workspace.validatePrintGeometry()
    precondition(workspace.printValidation.label == "Pass")
    precondition(workspace.resize(to: DimensionTarget(dimension: .height, value: 5, unit: .millimeter), changingPin: false))
    guard case .stale = workspace.printValidation else { fatalError("Resize kept old pass") }
    await workspace.validatePrintGeometry()

    await workspace.open(URL(fileURLWithPath: "Fixtures/Import/block.obj"))
    workspace.pendingUnits = nil // Cancel the unit picker.
    precondition(workspace.printValidation.label == "Pass")
    await workspace.open(URL(fileURLWithPath: "Fixtures/Import/block.3mf"))
    guard case .unchecked = workspace.printValidation else { fatalError("A new model inherited the old report") }

    // Queue an edit when the check starts, before the worker can publish its snapshot.
    let removeCap = workspace.$printValidation.sink { state in
        guard case .checking = state else { return }
        DispatchQueue.main.async {
            let model = workspace.activeModel!
            var changed = model.mesh
            changed.removeFaces(withIDs: [2, 3])
            try! workspace.commit(changed, basedOn: model)
        }
    }
    await workspace.validatePrintGeometry()
    await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
    removeCap.cancel()
    guard case .stale = workspace.printValidation else { fatalError("A late result overwrote the edit") }
}

try checkPrintDefects()
try await checkPrintInspection()
print("Print checks passed for local defects, scale independence, issue highlights and result invalidation.")
