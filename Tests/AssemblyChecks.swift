import Foundation
import SceneKit

let assemblyDirectory = URL(fileURLWithPath: "Fixtures/Import/Assemblies")
typealias Bounds = (SIMD3<Double>, SIMD3<Double>)

@MainActor
func checkAssembly(_ file: String, _ boxes: [Bounds]) async throws {
    let workspace = Workspace()
    let url = assemblyDirectory.appendingPathComponent(file)
    await workspace.open(url)
    guard let model = workspace.activeModel, let assembly = model.mesh.assembly else {
        fatalError(workspace.modelError ?? "No assembly")
    }
    let mesh = model.mesh
    let repeated = try MeshImport.read(url)
    precondition(repeated.mesh == mesh && model.unit == .millimeter)
    precondition(assembly.buildItems.count == 2 && assembly.occurrences.count == boxes.count)
    precondition(mesh.vertices.count == 8 * boxes.count && mesh.faces.count == 12 * boxes.count)
    for (n, occurrence) in assembly.occurrences.enumerated() {
        precondition(occurrence.importedVertices == n * 8..<(n + 1) * 8)
        precondition(occurrence.importedFaceIDs == n * 12..<(n + 1) * 12)
        var object = assembly.buildItems[occurrence.buildIndex].object
        for index in occurrence.componentIndices { object = assembly.objects[object]!.components[index].object }
        precondition(object == occurrence.object && assembly.objects[object]!.components.isEmpty)
        let points = mesh.vertices[occurrence.importedVertices]
        let low = points.reduce(SIMD3<Double>(repeating: .infinity), simd_min)
        let high = points.reduce(SIMD3<Double>(repeating: -.infinity), simd_max)
        precondition(simd_distance(low, boxes[n].0) < 0.0001 && simd_distance(high, boxes[n].1) < 0.0001)
        for face in mesh.faces[occurrence.importedFaceIDs] {
            let v = face.vertices
            precondition(occurrence.importedFaceIDs.contains(face.id))
            precondition([v.x, v.y, v.z].allSatisfy(occurrence.importedVertices.contains))
            let a = mesh.vertices[v.x], b = mesh.vertices[v.y], c = mesh.vertices[v.z]
            // Every triangle, including on a mirrored leaf, faces away from the box center.
            precondition(simd_dot(simd_cross(b - a, c - a), a - (high + low) / 2) > 0)
        }
    }
    if file == "repeated-block.3mf" {
        precondition(Set(assembly.occurrences.map(\.object)).count == 1)
        precondition(assembly.occurrences.map(\.componentIndices) == [[0, 0], [1, 0], [0]])
    }
    let view = ModelViewport.Coordinator()
    view.update(mesh: mesh, selection: [0], point: 0)
    precondition(view.displayed == mesh && view.positions.count == mesh.vertices.count)

    try workspace.applyManualEdit(.movePoint(0, axis: .height), basedOn: model, distance: 1, unit: .millimeter)
    let edited = workspace.activeModel!
    precondition(edited.mesh.vertices[0] == mesh.vertices[0] + [0, 0, 1])
    let op = ModelingOperation(scope: .revision(edited), instruction: "Move the first corner to the right.")
    let vertex = ModelingInput.Vertex(id: 0, position: edited.mesh.vertices[0] + [1, 0, 0])
    let patch = AgentMeshPatch(vertices: [vertex], faces: [], removedFaceIDs: [],
                               requestedDimensions: [], unsupportedConstraints: [])
    try ModelingProposal(operation: op, patch: patch).apply(to: workspace)
    let final = workspace.activeModel!
    precondition(final.mesh.vertices[0] == vertex.position && final.mesh.faces == mesh.faces)
    precondition(final.mesh.vertices.dropFirst() == mesh.vertices.dropFirst() && final.mesh.assembly == assembly)
    view.update(mesh: final.mesh, selection: [0], point: 0)
    precondition(view.displayed == final.mesh)
    print("\(file): occurrence placements, identities, winding, SceneKit and both edit paths passed.")
}

try await checkAssembly("bambu-blocks.3mf", [([90.00001, 100.99999, 0], [110.00001, 110.99999, 5]),
                                            ([90, 89.00003, 0], [110, 99.00003, 5])])
try await checkAssembly("orca-blocks.3mf", [([90, 101, 0], [110, 111, 5]),
                                           ([90.000001, 89, 0], [110.000001, 99, 5])])
try await checkAssembly("repeated-block.3mf", [([88, 55, 10], [98, 75, 15]),
                                              ([88, 90, 10], [98, 110, 15]),
                                              ([200, 0, 0], [220, 10, 5])])

@MainActor
func checkFailedReplacements() async throws {
    let workspace = Workspace()
    await workspace.open(assemblyDirectory.appendingPathComponent("repeated-block.3mf"))
    try workspace.applyManualEdit(.movePoint(0, axis: .height), basedOn: workspace.activeModel!,
                                  distance: 1, unit: .millimeter)
    workspace.pinCurrent(.width)
    let before = workspace.activeModel!
    let directory = URL(fileURLWithPath: CommandLine.arguments[1])
    let errors = ["missing-part": "block.model", "missing-relationship": "relationship", "missing-object": "object 31",
                  "late-missing-object": "object 31", "child-cross-part": "cross-part", "external-start": "External",
                  "invalid-index": "vertex", "invalid-xml": "XML", "invalid-transform": "transform",
                  "cyclic": "Cyclic", "external-path": "external", "external-relationship": "External",
                  "escape": "path", "unknown-extension": "extension"]
    for (file, message) in errors.sorted(by: { $0.key < $1.key }) {
        workspace.modelError = nil
        await workspace.open(directory.appendingPathComponent(file + ".3mf"))
        let detail = workspace.modelError?.split(separator: "\n").dropFirst().joined(separator: "\n")
        precondition(detail?.contains(message) == true, "\(file): \(workspace.modelError ?? "no error")")
        let after = workspace.activeModel!
        precondition(after.id == before.id && after.mesh == before.mesh && after.pins == before.pins)
        precondition(workspace.pendingUnits == nil)
    }
    for ext in ["stl", "obj"] {
        await workspace.open(assemblyDirectory.deletingLastPathComponent().appendingPathComponent("block." + ext))
        precondition(workspace.pendingUnits != nil && workspace.pendingUnits?.unit == nil)
        workspace.pendingUnits = nil // Cancel in UnitChoiceView.
        precondition(workspace.activeModel?.id == before.id && workspace.activeModel?.mesh == before.mesh)
        precondition(workspace.activeModel?.pins == before.pins)
    }
    print("\(errors.count) failed opens and both canceled unit selections preserved the edited, pinned assembly.")
}
try await checkFailedReplacements()
