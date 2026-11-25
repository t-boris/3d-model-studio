import Foundation
import simd

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fixtures = URL(fileURLWithPath: "Fixtures/Import", isDirectory: true)

@MainActor
func writeExport(_ workspace: Workspace, _ dialogs: ScriptedFileDialogs, _ name: String) async throws -> WorkspaceModel {
    let url = output.appendingPathComponent(name)
    dialogs.destination = url
    let result = await workspace.exportCore3MF()
    precondition(result == .written, workspace.modelError ?? "Export failed")
    guard case .current(let report) = workspace.printValidation, report.passed else { fatalError("Missing export pass") }
    let file = try MeshImport.read(url)
    precondition(file.unit == .millimeter && PrintGeometryReport(mesh: file.mesh).passed)
    return try file.model(in: .millimeter)
}

@MainActor
func checkWorkspaceExport() async throws {
    let dialogs = ScriptedFileDialogs(choice: .discard)
    let workspace = Workspace(dialogs: dialogs)
    workspace.newBlock()
    for (axis, length) in [(ModelDimension.width, 24.0), (.depth, 12), (.height, 8)] {
        precondition(workspace.resize(to: .init(dimension: axis, value: length, unit: .millimeter), changingPin: false))
    }
    let original = workspace.activeModel!
    let written = try await writeExport(workspace, dialogs, "created.3mf")
    precondition(written.extents == [24, 12, 8] && written.mesh.faces == original.mesh.faces)
    precondition(written.mesh.vertices == original.mesh.vertices && workspace.hasUnsavedChanges)
    let url = dialogs.destination!
    let existing = try Data(contentsOf: url)
    var openMesh = original.mesh
    openMesh.removeFaces(withIDs: [3])
    try workspace.commit(openMesh, basedOn: original)
    dialogs.events = []
    let failure = await workspace.exportCore3MF()
    precondition(failure == .invalidGeometry && dialogs.events.isEmpty && workspace.modelError == nil)
    guard case .current(let report) = workspace.printValidation else { fatalError("Expected print inspector issues") }
    precondition(report.issues.count == 3 && report.issues.allSatisfy { $0.problem == .boundary })
    precondition(Set(report.issues.flatMap(\.faces)) == [2, 9, 11])
    precondition(Set(report.issues.compactMap(\.edge)) == [SIMD2(4, 6), SIMD2(6, 7), SIMD2(4, 7)])
    let retained = try Data(contentsOf: url)
    precondition(retained == existing && workspace.activeModel!.mesh == openMesh)

    try workspace.commit(original.mesh, basedOn: workspace.activeModel!)
    var editBlocked = false
    dialogs.onPick = {
        editBlocked = !workspace.resize(to: .init(dimension: .height, value: 77, unit: .millimeter), changingPin: false)
    }
    let repaired = try await writeExport(workspace, dialogs, "created.3mf")
    precondition(editBlocked && repaired.mesh.vertices == original.mesh.vertices)
    dialogs.onPick = nil
    dialogs.destination = nil
    let cancelled = await workspace.exportCore3MF()
    precondition(cancelled == .cancelled && workspace.hasUnsavedChanges)
    dialogs.destination = output // Atomic write cannot replace a directory.
    let failedWrite = await workspace.exportCore3MF()
    precondition(failedWrite == .failed && workspace.modelError != nil && workspace.activeModel!.mesh == original.mesh)
    workspace.modelError = nil

    await workspace.open(fixtures.appendingPathComponent("block.3mf"))
    precondition(workspace.activeModel!.unit == .centimeter)
    precondition(workspace.resize(to: .init(dimension: .height, value: 7, unit: .millimeter), changingPin: false))
    let imported = try await writeExport(workspace, dialogs, "centimeter.3mf")
    precondition(imported.extents == [20, 10, 7])
    let (low, high) = imported.mesh.surfaceBounds
    precondition(low == .zero && high == [20, 10, 7])
    for ext in ["obj", "stl"] {
        await workspace.open(fixtures.appendingPathComponent("block." + ext))
        workspace.acceptUnit(.inch)
        precondition(workspace.resize(to: .init(dimension: .width, value: 3, unit: .inch), changingPin: false))
        let export = try await writeExport(workspace, dialogs, "inch-\(ext).3mf")
        precondition(simd_distance(export.extents, [76.2, 254, 127]) < 1e-10)
    }
    print("Edited new, centimeter, STL and OBJ exports, exact failed edges, repair, cancellation and write failure passed.")
}

func compareOccurrences(_ model: WorkspaceModel, _ written: WorkspaceModel) {
    let source = model.mesh.assembly!, result = written.mesh.assembly!
    precondition(result.buildItems.count == source.buildItems.count && result.occurrences.count == source.occurrences.count)
    precondition(result.objects.keys.allSatisfy { $0.part == result.startPart })
    func compareReference(_ before: ThreeMFAssembly.Reference, _ after: ThreeMFAssembly.Reference, unit: MeshUnit) {
        let a = before.transform, b = after.transform
        precondition(a.x == b.x && a.y == b.y && a.z == b.z)
        precondition(simd_distance(a.origin * unit.millimetersPerUnit, b.origin) < 1e-8)
        let originalObject = source.objects[before.object]!, exportedObject = result.objects[after.object]!
        precondition(originalObject.name == exportedObject.name && exportedObject.unit == .millimeter)
        precondition(originalObject.components.count == exportedObject.components.count)
        for (old, new) in zip(originalObject.components, exportedObject.components) {
            compareReference(old, new, unit: originalObject.unit)
        }
    }
    for (old, new) in zip(source.buildItems, result.buildItems) {
        compareReference(old, new, unit: model.unit)
    }
    for (before, after) in zip(source.occurrences, result.occurrences) {
        precondition(before.buildIndex == after.buildIndex && before.componentIndices == after.componentIndices)
        precondition(source.objects[before.object]!.name == result.objects[after.object]!.name)
        let expected = model.mesh.faces.filter { before.contains(faceID: $0.id) }
        let actual = written.mesh.faces.filter { after.contains(faceID: $0.id) }
        precondition(actual.count == expected.count)
        for (a, b) in zip(expected, actual) {
            for i in 0..<3 {
                let mm = model.mesh.vertices[a.vertices[i]] * model.unit.millimetersPerUnit
                precondition(simd_distance(mm, written.mesh.vertices[b.vertices[i]]) < 0.000001)
            }
        }
    }
}

@MainActor
func checkAssemblyExport(_ name: String, low: [SIMD3<Double>], high: [SIMD3<Double>]) async throws {
    let dialogs = ScriptedFileDialogs(choice: .discard)
    let workspace = Workspace(dialogs: dialogs)
    let source = output.appendingPathComponent("input.3mf")
    try FileManager.default.copyItem(at: fixtures.appendingPathComponent("Assemblies/\(name).3mf"), to: source)
    await workspace.open(source)
    let original = workspace.activeModel!
    let assembly = original.mesh.assembly!
    let target = assembly.occurrences[1]
    let top = Set(original.mesh.faces.filter { face in
        target.contains(faceID: face.id) && (0..<3).allSatisfy { abs(original.mesh.vertices[face.vertices[$0]].z - high[1].z + 2) < 1e-6 }
    }.map(\.id))
    precondition(top.count == 2)
    try workspace.applyManualEdit(.extrude(top), basedOn: original, distance: 2, unit: .millimeter)
    let edited = workspace.activeModel!
    let direct = try await writeExport(workspace, dialogs, "\(name).3mf")
    compareOccurrences(edited, direct)
    for (i, occurrence) in direct.mesh.assembly!.occurrences.enumerated() {
        let points = direct.mesh.vertices[occurrence.importedVertices]
        precondition(simd_distance(points.reduce(SIMD3(repeating: .infinity), simd_min), low[i]) < 0.0001)
        precondition(simd_distance(points.reduce(SIMD3(repeating: -.infinity), simd_max), high[i]) < 0.0001)
    }
    if name == "repeated-block" {
        let leaves = direct.mesh.assembly!.occurrences.map(\.object)
        precondition(leaves[0] == leaves[2] && leaves[1] != leaves[0])
    }
    let archive = output.appendingPathComponent("\(name).studio3d")
    dialogs.destination = archive
    let saved = await workspace.save()
    precondition(saved)
    try FileManager.default.removeItem(at: source)
    let restored = Workspace(dialogs: dialogs)
    await restored.open(archive)
    precondition(restored.activeModel!.mesh == edited.mesh)
    let reopened = try await writeExport(restored, dialogs, "\(name)-reopened.3mf")
    compareOccurrences(edited, reopened)
    precondition(direct.mesh == reopened.mesh && !restored.hasUnsavedChanges)
    print("\(name): edited occurrence 2, all world corners and bounds, hierarchy, winding and source-independent reopen passed.")
}

@MainActor
func checkConversionFailure() async throws {
    // Force cancellation of significant digits during inversion of the build placement.
    // The source is printable, but re-reading the actual package produces collapsed faces.
    var mesh = try WorkspaceModel.newBlock().mesh
    // Replacing the first face gives it a workspace ID outside the serialized range.
    let corners = mesh.faces[0].vertices
    mesh.removeFaces(withIDs: [0])
    let replacementID = mesh.nextFaceID
    mesh.addFace(corners.x, corners.y, corners.z)
    let id = ThreeMFAssembly.ObjectID(part: "model", id: 1)
    let item = try ThreeMFAssembly.Reference(object: id, transform: .init("1 0 0 0 1 0 0 0 1 1e18 0 0"), uuid: nil)
    mesh.assembly = ThreeMFAssembly(startPart: id.part, buildItems: [item],
        objects: [id: .init(name: nil, unit: .millimeter, components: [])],
        occurrences: [.init(object: id, buildIndex: 0, componentIndices: [], importedVertices: 0..<8,
                            importedFaceIDs: 0..<12, addedFaceIDRanges: [replacementID..<mesh.nextFaceID])])
    let dialogs = ScriptedFileDialogs(choice: .discard)
    let workspace = Workspace(dialogs: dialogs)
    try workspace.commitCreation(mesh, unit: .millimeter, requested: [])
    await workspace.validatePrintGeometry()
    guard case .current(let source) = workspace.printValidation, source.passed else { fatalError("Expected a printable source") }

    let destination = output.appendingPathComponent("precision-repaired.3mf")
    let existing = try Data(contentsOf: output.appendingPathComponent("created.3mf"))
    try existing.write(to: destination)
    dialogs.destination = destination
    let result = await workspace.exportCore3MF()
    precondition(result == .invalidGeometry && dialogs.events.isEmpty && workspace.activeModel?.mesh == mesh)
    guard case .current(let report) = workspace.printValidation else { fatalError("Expected readback failure in the inspector") }
    precondition(report.issues.contains { $0.problem == .degenerate && $0.faces == [replacementID] })
    precondition(report.issues.allSatisfy { !$0.faces.contains(0) })
    let retained = try Data(contentsOf: destination)
    precondition(retained == existing)

    // 256 mm survives the round trip through this extreme translation exactly.
    precondition(workspace.resize(to: .init(dimension: .width, value: 256, unit: .millimeter), changingPin: false))
    let repaired = try await writeExport(workspace, dialogs, destination.lastPathComponent)
    precondition(repaired.extents == [256, 10, 10])
    print("Serialized collapse identified workspace face \(replacementID), preserved destination bytes, and exported after repair.")
}

try await checkWorkspaceExport()
try await checkConversionFailure()
try await checkAssemblyExport("repeated-block", low: [[88, 55, 10], [88, 90, 10], [200, 0, 0]],
                              high: [[98, 75, 15], [98, 110, 17], [220, 10, 5]])
try await checkAssemblyExport("bambu-blocks", low: [[90.00001, 100.99999, 0], [90, 89.00003, 0]],
                              high: [[110.00001, 110.99999, 5], [110, 99.00003, 7]])
try await checkAssemblyExport("orca-blocks", low: [[90, 101, 0], [90.000001, 89, 0]],
                              high: [[110, 111, 5], [110.000001, 99, 7]])
