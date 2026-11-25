import Foundation

private func checkIssueHighlight(_ issue: PrintGeometryReport.Issue, in mesh: EditableMesh,
                                 viewport: ModelViewport.Coordinator) {
    viewport.update(mesh: mesh, selection: Set(issue.faces), point: issue.markerVertex,
                    inspectionEdge: issue.edge, inspectingIssue: true)
    let indices = mesh.faces.indices.filter { issue.faces.contains(mesh.faces[$0].id) }
    precondition(viewport.faceGroups.last == indices)
    let outline = viewport.faceOutline.geometry!
    let lines = outline.elements[0]
    precondition(lines.primitiveType == .line && lines.primitiveCount == indices.count * 3)
    let endpoints = lines.data.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
    let expected = indices.flatMap { index -> [UInt32] in
        let a = UInt32(index * 3)
        return [a, a + 1, a + 1, a + 2, a + 2, a]
    }
    precondition(endpoints == expected && outline.firstMaterial?.readsFromDepthBuffer == false)
    precondition(viewport.shownEdge == issue.edge)
    precondition(viewport.edgeOverlay.geometry?.elements.first?.primitiveCount == issue.edge.map { _ in 1 })
    precondition(!viewport.marker.isHidden && viewport.marker.geometry?.firstMaterial?.readsFromDepthBuffer == false)
    let marker = viewport.marker.position, expectedPoint = viewport.positions[issue.markerVertex]
    precondition(simd_distance(SIMD3<Float>(marker), SIMD3<Float>(expectedPoint)) < 1e-6)
}

private func edgeFaces(_ mesh: EditableMesh, _ edge: SIMD2<Int>) -> [Int] {
    mesh.faces.compactMap { face in
        let v = face.vertices
        let corners = [v.x, v.y, v.z]
        return corners.contains(edge.x) && corners.contains(edge.y) ? face.id : nil
    }
}

private func checkPrintDefects() throws {
    let block = try WorkspaceModel.newBlock().mesh
    let viewport = ModelViewport.Coordinator()
    let edges: Set<SIMD2<Int>> = [SIMD2(0, 1), SIMD2(0, 2), SIMD2(1, 2)]
    var flipped = block
    flipped.replaceCorners(at: 0, with: [0, 1, 2])
    let winding = PrintGeometryReport(mesh: flipped).issues
    precondition(Set(winding.compactMap(\.edge)) == edges && winding.count == edges.count)
    for issue in winding {
        precondition(issue.problem == .winding && issue.faces == edgeFaces(flipped, issue.edge!))
        checkIssueHighlight(issue, in: flipped, viewport: viewport)
    }

    var duplicate = block
    duplicate.addFace(1, 2, 0)
    let copies = PrintGeometryReport(mesh: duplicate).issues
    precondition(copies.count == 4)
    let duplicateIssues = copies.filter { $0.problem == .duplicate }
    precondition(duplicateIssues.map(\.faces) == [[0, 12]] && duplicateIssues[0].location.contains("2 faces"))
    checkIssueHighlight(duplicateIssues[0], in: duplicate, viewport: viewport)
    let crowdedEdges = copies.filter { $0.problem == .nonManifold }
    precondition(Set(crowdedEdges.compactMap(\.edge)) == edges && crowdedEdges.count == edges.count)
    for issue in crowdedEdges {
        precondition(issue.faces == edgeFaces(duplicate, issue.edge!))
        checkIssueHighlight(issue, in: duplicate, viewport: viewport)
    }

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
    checkIssueHighlight(folded.first { $0.problem == .degenerate }!, in: sliver, viewport: viewport)
    sliver.replaceCorners(at: 0, with: [2, 2, 2])
    let point = PrintGeometryReport(mesh: sliver).issues
    precondition(point.count == 1 && point[0].problem == .degenerate && point[0].markerVertex == 2)
    checkIssueHighlight(point[0], in: sliver, viewport: viewport)
    viewport.update(mesh: sliver, selection: [0], point: 2)
    precondition(viewport.faceOutline.geometry == nil && viewport.marker.geometry?.firstMaterial?.readsFromDepthBuffer == true)
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
        precondition(issue.problem == .boundary && issue.faces == edgeFaces(open, issue.edge!))
        checkIssueHighlight(issue, in: open, viewport: view)
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

@MainActor
private func checkManualPrintFailure(source: String?) async throws {
    let workspace = Workspace()
    if let source {
        await workspace.open(URL(fileURLWithPath: "Fixtures/Import/" + source))
        if workspace.pendingUnits != nil { workspace.acceptUnit(.inch) }
    } else {
        workspace.newBlock()
    }
    let model = workspace.activeModel!
    let mesh = model.mesh
    let v = mesh.faces[0].vertices
    let edges = [SIMD2(v.x, v.y), SIMD2(v.y, v.z), SIMD2(v.z, v.x)]
    let edge = edges.first {
        let offset = mesh.vertices[$0.y] - mesh.vertices[$0.x]
        return [offset.x, offset.y, offset.z].filter { $0 != 0 }.count == 1
    }!
    let offset = mesh.vertices[edge.y] - mesh.vertices[edge.x]
    let axis = ModelDimension.allCases.first { offset[$0.axis] != 0 }!
    await workspace.validatePrintGeometry()
    precondition(workspace.printValidation.label == "Pass", source ?? "new block")

    let move = ManualMeshEdit.movePoint(edge.x, axis: axis)
    let distance = offset[axis.axis]
    try workspace.applyManualEdit(move, basedOn: model, distance: distance, unit: model.unit)
    precondition(workspace.printValidation.label == "Outdated · Run again")
    await workspace.validatePrintGeometry()
    guard case .current(let report) = workspace.printValidation else { fatalError("Missing manual check") }
    precondition(!report.passed && report.issues.allSatisfy { $0.problem == .degenerate && $0.edge == nil },
                 source ?? "new block")
    precondition(report.issues.flatMap(\.faces) == edgeFaces(mesh, edge), source ?? "new block")
    let edited = workspace.activeModel!
    let viewport = ModelViewport.Coordinator()
    for issue in report.issues {
        checkIssueHighlight(issue, in: edited.mesh, viewport: viewport)
    }
    try workspace.applyManualEdit(move, basedOn: edited, distance: -distance, unit: model.unit)
    precondition(workspace.printValidation.label == "Outdated · Run again")
    await workspace.validatePrintGeometry()
    precondition(workspace.printValidation.label == "Pass")
}

try checkPrintDefects()
try await checkPrintInspection()
for source: String? in [nil, "block.stl", "block.obj", "block.3mf", "Assemblies/bambu-blocks.3mf",
                       "Assemblies/orca-blocks.3mf", "Assemblies/repeated-block.3mf"] {
    try await checkManualPrintFailure(source: source)
}
print("Print checks passed for all five defects, issue highlights, result invalidation and manual failure/repair on seven model origins.")
