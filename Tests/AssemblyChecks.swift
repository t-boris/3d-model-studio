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
func checkConversationalRemesh() async throws {
    let workspace = Workspace()
    await workspace.open(assemblyDirectory.appendingPathComponent("repeated-block.3mf"))
    let original = workspace.activeModel!
    let assembly = original.mesh.assembly!
    let index = 1
    let leaf = assembly.occurrences[index]
    let face = original.mesh.faces.first { leaf.contains(faceID: $0.id) }!
    let v = face.vertices
    let center = (original.mesh.vertices[v.x] + original.mesh.vertices[v.y] + original.mesh.vertices[v.z]) / 3
    let newVertex = ModelingInput.Vertex(id: -1, position: center)
    let subdivision: [ModelingInput.Face] = [.init(id: -1, vertices: [v.z, v.x, -1]),
                                             .init(id: face.id, vertices: [v.x, v.y, -1]),
                                             .init(id: -2, vertices: [v.y, v.z, -1])]
    let op = ModelingOperation(scope: .revision(original), instruction: "Subdivide the triangle")
    func patch(_ faces: [ModelingInput.Face]) -> AgentMeshPatch {
        AgentMeshPatch(vertices: [newVertex], faces: faces, removedFaceIDs: [], requestedDimensions: [], unsupportedConstraints: [])
    }
    let siblingVertex = assembly.occurrences[0].importedVertices.lowerBound
    do {
        _ = try ModelingProposal(operation: op, patch: patch(subdivision + [.init(id: -3, vertices: [v.x, siblingVertex, -1])]))
        fatalError("Ambiguous occurrence ownership")
    } catch {
        precondition(error.localizedDescription.contains("occurrence"))
        precondition(workspace.activeModel!.mesh == original.mesh)
    }
    try ModelingProposal(operation: op, patch: patch(subdivision)).apply(to: workspace)
    let edited = workspace.activeModel!
    let reopened = try EditableModelFile(data: EditableModelFile(model: edited).encoded()).model
    precondition(reopened.mesh == edited.mesh)
    let mapped = reopened.mesh.assembly!
    precondition(mapped.objects == assembly.objects && mapped.buildItems == assembly.buildItems)
    precondition(mapped.occurrences[0] == assembly.occurrences[0] && mapped.occurrences[2] == assembly.occurrences[2])
    for added in original.mesh.nextFaceID..<edited.mesh.nextFaceID {
        precondition(mapped.occurrences.filter { $0.contains(faceID: added) } == [mapped.occurrences[index]])
    }
    let siblings = original.mesh.faces.filter { !leaf.contains(faceID: $0.id) }
    precondition(siblings == edited.mesh.faces.filter { !mapped.occurrences[index].contains(faceID: $0.id) })
    precondition(edited.mesh.vertices.dropLast() == original.mesh.vertices[...])
    print("Conversational subdivision preserved repeated occurrence ownership after reopening; a cross-occurrence addition was rejected.")
}
try await checkConversationalRemesh()

@MainActor
func checkManualAssembly(_ file: String) async throws {
    let workspace = Workspace()
    await workspace.open(assemblyDirectory.appendingPathComponent(file))
    let original = workspace.activeModel!
    let assembly = original.mesh.assembly!
    let occurrence = assembly.occurrences[0]
    let top = original.mesh.vertices[occurrence.importedVertices].map(\.z).max()!
    let cap = original.mesh.faces.filter { face in
        occurrence.contains(faceID: face.id) && (0..<3).allSatisfy { original.mesh.vertices[face.vertices[$0]].z == top }
    }
    precondition(cap.count == 2)
    let selection = Set(cap.map(\.id))

    func edit(_ operation: ManualMeshEdit, _ distance: Double, _ unit: MeshUnit) throws {
        try workspace.applyManualEdit(operation, basedOn: workspace.activeModel!, distance: distance, unit: unit)
    }

    workspace.pinCurrent(.width)
    workspace.pinCurrent(.depth)
    workspace.pinCurrent(.height)
    let pinned = workspace.activeModel!
    do {
        try edit(.extrude(selection), 0.2, .centimeter)
        fatalError("A pinned height must reject extrusion.")
    } catch {
        precondition(error.localizedDescription.contains("Pinned Height (Z)"))
    }
    precondition(workspace.activeModel!.mesh == pinned.mesh && workspace.activeModel!.pins == pinned.pins)
    workspace.unpin(.height)

    try edit(.movePoint(cap[0].vertices.x, axis: .height), 1000, .micron)
    precondition(workspace.activeModel!.mesh.assembly == assembly)
    precondition(workspace.activeModel!.mesh.vertices[cap[0].vertices.x].z == top + 1)
    try edit(.movePoint(cap[0].vertices.x, axis: .height), -1, .millimeter)
    try edit(.reshape(selection, axis: .height), 1000, .micron)
    precondition(workspace.activeModel!.mesh.assembly == assembly)
    try edit(.extrude(selection), 0.2, .centimeter)

    let edited = workspace.activeModel!
    let editedAssembly = edited.mesh.assembly!
    precondition(editedAssembly.startPart == assembly.startPart && editedAssembly.buildItems == assembly.buildItems)
    precondition(editedAssembly.objects == assembly.objects)
    precondition(editedAssembly.occurrences.dropFirst() == assembly.occurrences.dropFirst())
    for sibling in assembly.occurrences.dropFirst() {
        precondition(edited.mesh.vertices[sibling.importedVertices] == original.mesh.vertices[sibling.importedVertices])
        precondition(edited.mesh.faces[sibling.importedFaceIDs] == original.mesh.faces[sibling.importedFaceIDs])
    }
    let walls = edited.mesh.faces.dropFirst(original.mesh.faces.count)
    precondition(walls.count == 8)
    precondition(edited.mesh.faces.prefix(original.mesh.faces.count).map(\.id) == original.mesh.faces.map(\.id))
    precondition(edited.mesh.vertices.suffix(4).allSatisfy { $0.z == top + 3 })
    for face in edited.mesh.faces {
        precondition(editedAssembly.occurrences.count { $0.contains(faceID: face.id) } == 1)
    }
    let owner = editedAssembly.occurrences[0]
    precondition(walls.allSatisfy { owner.contains(faceID: $0.id) })
    let usedVertices = Set(edited.mesh.faces.filter { owner.contains(faceID: $0.id) }.flatMap {
        [$0.vertices.x, $0.vertices.y, $0.vertices.z]
    })
    precondition(usedVertices == Set(occurrence.importedVertices).union(original.mesh.vertices.count..<edited.mesh.vertices.count))
    precondition(edited.pins == pinned.pins.filter { $0.dimension != .height })
    await workspace.validatePrintGeometry()
    precondition(workspace.printValidation.label == "Pass")

    let data = try EditableModelFile(model: edited).encoded()
    var reopened = try EditableModelFile(data: data).model
    precondition(reopened.mesh == edited.mesh && reopened.pins == edited.pins && reopened.unit == edited.unit)
    // The first two wall triangles share the same rim edge and form a planar patch.
    // Exercise an extrusion whose cap consists of already-generated face IDs.
    let wallSelection = Set(walls.prefix(2).map(\.id))
    reopened.unpin(.width)
    reopened.unpin(.depth)
    let extensionMesh = try ManualMeshEdit.extrude(wallSelection).proposal(for: reopened, distance: 1, unit: .millimeter)
    try reopened.commit(extensionMesh)
    let extensionWalls = reopened.mesh.faces.dropFirst(edited.mesh.faces.count)
    precondition(extensionWalls.count == 8)
    precondition(extensionWalls.allSatisfy { reopened.mesh.assembly!.occurrences[0].contains(faceID: $0.id) })
    precondition(reopened.mesh.assembly!.occurrences.dropFirst() == assembly.occurrences.dropFirst())

    func heightTarget(_ millimeters: Double) -> DimensionTarget {
        DimensionTarget(dimension: .height, value: millimeters / 10, unit: .centimeter)
    }
    let height = edited.extents.z
    precondition(workspace.resize(to: heightTarget(height + 1), changingPin: false))
    precondition(workspace.activeModel!.extents.z == height + 1 && workspace.activeModel!.pins == edited.pins)
    precondition(workspace.resize(to: heightTarget(height + 2), changingPin: false))
    precondition(workspace.activeModel!.extents.z == height + 2 && workspace.activeModel!.pins == edited.pins)
    workspace.pinCurrent(.height)
    let newPin = heightTarget(height + 3)
    precondition(workspace.resize(to: newPin, changingPin: true))
    let resized = workspace.activeModel!
    precondition(resized.extents.z == height + 3 && resized.pins == edited.pins + [newPin])
    precondition(!workspace.resize(to: heightTarget(height + 4), changingPin: false))
    precondition(workspace.modelError?.contains("Pinned Height (Z)") == true)
    precondition(workspace.activeModel!.mesh == resized.mesh && workspace.activeModel!.pins == resized.pins)
    precondition(resized.mesh.assembly == editedAssembly)
    print("\(file): all manual tools, extrusion ownership and isolation, archive round trip, and explicit-unit pin transactions passed.")
}

for file in ["bambu-blocks.3mf", "orca-blocks.3mf", "repeated-block.3mf"] {
    try await checkManualAssembly(file)
}

@MainActor
func checkFailedReplacements() async throws {
    let workspace = Workspace(dialogs: ScriptedFileDialogs(choice: .discard))
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
