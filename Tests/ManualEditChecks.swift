import Foundation
import SceneKit

private func expectFailure(_ reason: String, _ action: () throws -> Void) {
    do {
        try action()
        fatalError("Expected rejection: \(reason)")
    } catch {
        precondition(error.localizedDescription.contains(reason), error.localizedDescription)
    }
}

private func checkClosedMesh(_ mesh: EditableMesh) {
    var edges: [SIMD2<Int>: [Int]] = [:]
    for face in mesh.faces {
        let v = face.vertices
        precondition(simd_length(simd_cross(mesh.vertices[v.y] - mesh.vertices[v.x],
                                           mesh.vertices[v.z] - mesh.vertices[v.x])) > 0)
        for j in 0..<3 {
            let a = v[j], b = v[(j + 1) % 3]
            edges[SIMD2(min(a, b), max(a, b)), default: []].append(a < b ? 1 : -1)
        }
    }
    precondition(edges.values.allSatisfy { $0.sorted() == [-1, 1] })
}

@MainActor
private func exercise(_ source: String?) async throws {
    let workspace = Workspace()
    if let source {
        await workspace.open(URL(fileURLWithPath: "Fixtures/Import/block." + source))
        if source != "3mf" { workspace.acceptUnit(.millimeter) }
    } else {
        workspace.newBlock()
    }
    let initial = workspace.activeModel!
    let topIDs: Set<Int> = [2, 3]
    let factor = initial.unit.millimetersPerUnit
    let topFaces = initial.mesh.faces.filter { topIDs.contains($0.id) }
    let topPoints = Set(topFaces.flatMap { [$0.vertices.x, $0.vertices.y, $0.vertices.z] })
    let point = topFaces[0].vertices.x

    let view = ModelViewport.Coordinator()
    view.update(mesh: initial.mesh, selection: [], point: point)
    precondition(view.marker.position.y == view.positions[point].y && !view.marker.isHidden)
    precondition(view.selection(element: 0, primitive: 2, near: view.positions[point])?.point == point)
    let initialPositions = view.positions
    func edit(_ edit: ManualMeshEdit, _ value: Double, _ unit: MeshUnit = .millimeter) throws {
        try workspace.applyManualEdit(edit, basedOn: workspace.activeModel!, distance: value, unit: unit)
    }

    await workspace.validatePrintGeometry()
    precondition(workspace.printValidation.label == "Pass")
    workspace.pinCurrent(.width)
    workspace.pinCurrent(.depth)
    workspace.pinCurrent(.height)
    let pinned = workspace.activeModel!
    for operation: ManualMeshEdit in [.movePoint(point, axis: .height), .reshape(topIDs, axis: .height), .extrude(topIDs)] {
        expectFailure("Pinned Height (Z)") {
            try workspace.applyManualEdit(operation, basedOn: initial, distance: 1, unit: .millimeter)
        }
        precondition(workspace.activeModel!.mesh == pinned.mesh && workspace.activeModel!.pins == pinned.pins)
    }
    precondition(workspace.printValidation.label == "Pass") // Pin-only changes and rejected edits.
    workspace.unpin(.height)
    try edit(.movePoint(point, axis: .height), 1000, .micron)
    guard case .stale = workspace.printValidation else { fatalError("Expected outdated manual result") }
    let moved = workspace.activeModel!
    precondition(moved.mesh.faces == initial.mesh.faces)
    precondition(moved.mesh.vertices.indices.filter { moved.mesh.vertices[$0] != initial.mesh.vertices[$0] } == [point])
    precondition(abs((moved.mesh.vertices[point].z - initial.mesh.vertices[point].z) * factor - 1) < 1e-12)
    view.update(mesh: moved.mesh, selection: [], point: point)
    // The display refits the model after an edit. Compare the picked corner to
    // a neighbor on the original top plane in that display coordinate system.
    let neighbor = topFaces[0].vertices.y
    precondition(initialPositions[point].y == initialPositions[neighbor].y)
    precondition(view.positions[point].y > view.positions[neighbor].y)
    try edit(.movePoint(point, axis: .height), -1)

    let offset = 7 - initial.extents.z * factor
    try edit(.reshape(topIDs, axis: .height), offset / 10, .centimeter)
    let reshaped = workspace.activeModel!
    precondition(reshaped.mesh.faces == initial.mesh.faces)
    for i in initial.mesh.vertices.indices {
        let old = initial.mesh.vertices[i], new = reshaped.mesh.vertices[i]
        precondition(old.x == new.x && old.y == new.y)
        let expectedZ = topPoints.contains(i) ? 7 : old.z * factor
        precondition(abs(new.z * factor - expectedZ) < 1e-12)
    }
    precondition(abs(reshaped.extents.z * factor - 7) < 1e-12)
    view.update(mesh: reshaped.mesh, selection: topIDs, point: nil)
    precondition(view.displayed == reshaped.mesh && view.marker.isHidden)
    // Cast a ray through a top triangle using SceneKit's actual element/primitive result.
    let v = topFaces[0].vertices
    let center = (SIMD3<Float>(view.positions[v.x]) + SIMD3<Float>(view.positions[v.y])
                  + SIMD3<Float>(view.positions[v.z])) / 3
    let scene = SCNScene()
    scene.rootNode.addChildNode(view.surface)
    SCNTransaction.flush()
    let ray = scene.rootNode.hitTestWithSegment(from: SCNVector3(center + SIMD3(0, 4, 0)),
                                              to: SCNVector3(center - SIMD3(0, 4, 0)), options: nil)
    let hit = ray.first!
    precondition(view.selection(element: hit.geometryIndex, primitive: hit.faceIndex, near: hit.localCoordinates)?.face == topFaces[0].id)

    try edit(.extrude(topIDs), 2)
    let extruded = workspace.activeModel!
    precondition(extruded.mesh.vertices.count == 12 && extruded.mesh.faces.count == 20)
    precondition(extruded.mesh.faces.prefix(12).map(\.id) == initial.mesh.faces.map(\.id))
    precondition(extruded.mesh.faces.prefix(12).filter { !topIDs.contains($0.id) } ==
                    initial.mesh.faces.filter { !topIDs.contains($0.id) })
    precondition(abs(extruded.extents.z * factor - 9) < 1e-12)
    precondition(extruded.pins.map(\.dimension) == [.width, .depth])
    checkClosedMesh(extruded.mesh)
    await workspace.validatePrintGeometry()
    precondition(workspace.printValidation.label == "Pass")
    view.update(mesh: extruded.mesh, selection: topIDs, point: nil)
    precondition(view.displayed == extruded.mesh && view.surface.geometry!.elements.map(\.primitiveCount) == [18, 2])
    try edit(.extrude([2]), 1)
    precondition(workspace.activeModel!.mesh.faces.count == 26)
    checkClosedMesh(workspace.activeModel!.mesh)

    let before = workspace.activeModel!
    expectFailure("flat patch") { try edit(.extrude([0, 2]), 1) }
    expectFailure("positive") { try edit(.extrude([2]), -2) }
    expectFailure("Select faces") { try edit(.reshape([999], axis: .width), 1) }
    expectFailure("Select a point") { try edit(.movePoint(-1, axis: .width), 1) }
    expectFailure("finite") { try edit(.extrude([2]), .nan) }
    expectFailure("model changed") {
        try workspace.applyManualEdit(.extrude(topIDs), basedOn: initial, distance: 1, unit: .millimeter)
    }
    precondition(workspace.activeModel!.mesh == before.mesh && workspace.activeModel!.pins == before.pins)

    // At this world position all four requested offsets round to 0.625 mm.
    // Measure the actual displacement for each operation before accepting it.
    var offsetMesh = initial.mesh
    for index in offsetMesh.vertices.indices { offsetMesh.vertices[index].z += 0x1p48 / factor }
    try workspace.commit(offsetMesh, basedOn: before)
    for operation: ManualMeshEdit in [.movePoint(point, axis: .height), .reshape(topIDs, axis: .height), .extrude(topIDs)] {
        for (microns, accepted) in [(614.9, false), (615, true), (635, true), (635.1, false)] {
            let snapshot = workspace.activeModel!
            if accepted {
                try edit(operation, microns, .micron)
                let result = workspace.activeModel!
                precondition((result.extents.z - snapshot.extents.z) * factor == 0.625)
                precondition(result.pins == snapshot.pins)
                try workspace.commit(offsetMesh, basedOn: result)
            } else {
                expectFailure("cannot be represented") { try edit(operation, microns, .micron) }
                precondition(workspace.activeModel!.mesh == snapshot.mesh)
                precondition(workspace.activeModel!.pins == snapshot.pins)
            }
        }
    }
    print("\(source ?? "New block"): all manual tools, viewport selection, shared topology, current pins, and inclusive displacement limits passed.")
}

for source: String? in [nil, "stl", "obj", "3mf"] { try await exercise(source) }

// An edit at a large coordinate may round to a different physical distance.
let block = try WorkspaceModel.newBlock()
var far = block.mesh
for i in far.vertices.indices { far.vertices[i].x += 1e16 }
let farModel = try WorkspaceModel(name: "Offset", unit: .millimeter, mesh: far)
expectFailure("cannot be represented") {
    _ = try ManualMeshEdit.movePoint(0, axis: .width).proposal(for: farModel, distance: 3, unit: .millimeter)
}
print("Unrepresentable numerical edit rejected.")

// Extrude an inclined triangulated patch with a shared center and no internal walls.
var patch = EditableMesh()
patch.vertices = [SIMD3(0, 0, 0), SIMD3(2, 0, 0), SIMD3(2, 2, 2), SIMD3(0, 2, 2), SIMD3(1, 1, 1)]
for i in 0..<4 { patch.addFace(i, (i + 1) % 4, 4) }
let region: Set<Int> = [0, 1, 2, 3]
func extrudePatch(_ mesh: EditableMesh, ids: Set<Int>) throws -> EditableMesh {
    let model = try WorkspaceModel(name: "Patch", unit: .millimeter, mesh: mesh)
    return try ManualMeshEdit.extrude(ids).proposal(for: model, distance: 1, unit: .millimeter)
}
let raised = try extrudePatch(patch, ids: region)
precondition(raised.vertices.count == 9 && raised.faces.count == 12)
let normal = simd_normalize(SIMD3<Double>(0, -1, 1))
for i in 0..<4 {
    for corner in 0..<3 {
        let old = patch.vertices[patch.faces[i].vertices[corner]]
        let new = raised.vertices[raised.faces[i].vertices[corner]]
        precondition(simd_distance(new - old, normal) < 1e-12)
    }
}
patch.vertices.append(contentsOf: [SIMD3(10, 0, 0), SIMD3(12, 0, 0), SIMD3(10, 2, 2)])
patch.addFace(5, 6, 7)
expectFailure("flat patch") { _ = try extrudePatch(patch, ids: [0, 4]) }
patch.addFace(4, 5, 6)
let sharedCenter = try extrudePatch(patch, ids: region)
precondition(sharedCenter.vertices[4] == patch.vertices[4] && sharedCenter.faces[5] == patch.faces[5])
print("Inclined patch normal, interior vertices, external neighbors and disconnected selection passed.")
