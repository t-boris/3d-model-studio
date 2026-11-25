import Foundation

private let legacy = URL(fileURLWithPath: "Fixtures/Save/version-1.studio3d")
private let fixtures = URL(fileURLWithPath: "Fixtures/Import")

@MainActor
private func retained(_ workspace: Workspace, _ original: WorkspaceModel) {
    let current = workspace.activeModel!
    precondition(current.id == original.id && current.mesh == original.mesh)
    precondition(current.unit == original.unit && current.pins == original.pins)
}

@MainActor
private func checkDirtyChanges(_ directory: URL) async throws {
    for imported in [false, true] {
        for change in ["geometry", "add pin", "change pin", "remove pin"] {
            let dialogs = ScriptedFileDialogs(choice: .cancel)
            let workspace = Workspace(dialogs: dialogs)
            if imported {
                await workspace.open(fixtures.appendingPathComponent("block.obj"))
                workspace.acceptUnit(.centimeter)
                precondition(!workspace.hasUnsavedChanges)
            } else {
                workspace.newBlock()
                precondition(workspace.hasUnsavedChanges)
            }
            if change == "change pin" || change == "remove pin" { workspace.pinCurrent(.width) }
            let archive = directory.appendingPathComponent("baseline.studio3d")
            dialogs.destination = archive
            let saved = await workspace.save()
            precondition(saved && !workspace.hasUnsavedChanges)
            let before = workspace.activeModel!
            let restored = try EditableModelFile.read(archive)
            precondition(restored.mesh == before.mesh && restored.pins == before.pins)
            precondition(restored.unit == (imported ? .centimeter : .millimeter))
            switch change {
            case "geometry": try workspace.applyManualEdit(.movePoint(0, axis: .height), basedOn: before,
                                                          distance: 0.25, unit: .millimeter)
            case "add pin": workspace.pinCurrent(.width)
            case "change pin":
                let unit: MeshUnit = imported ? .millimeter : .centimeter
                let value = before.extents.x * before.unit.millimetersPerUnit / unit.millimetersPerUnit
                let target = DimensionTarget(dimension: .width, value: value, unit: unit)
                precondition(workspace.resize(to: target, changingPin: true))
            default: workspace.unpin(.width)
            }
            let edited = workspace.activeModel!
            if change == "geometry" { precondition(edited.pins == before.pins && edited.mesh != before.mesh) }
            else { precondition(edited.mesh == before.mesh && edited.pins != before.pins) }
            dialogs.events.removeAll()
            await workspace.open()
            let quit = await workspace.shouldQuit()
            precondition(!quit && dialogs.events == ["confirm open", "confirm quit"])
            retained(workspace, edited)
            precondition(workspace.hasUnsavedChanges)

            // Putting the saved content back clears the prompt without another save.
            switch change {
            case "geometry": try workspace.commit(before.mesh, basedOn: edited)
            case "add pin": workspace.unpin(.width)
            case "change pin": precondition(workspace.resize(to: before.pins[0], changingPin: true))
            default: workspace.pinCurrent(.width)
            }
            retained(workspace, before)
            let cleanQuit = await workspace.shouldQuit()
            precondition(cleanQuit && !workspace.hasUnsavedChanges && dialogs.events.count == 2)
        }
    }
    print("New and imported models: geometry and three independent pin changes prompted for Open and Quit. Reverted changes were clean.")
}

@MainActor
private func checkInterruptions(_ directory: URL) async throws {
    let dialogs = ScriptedFileDialogs(choice: .discard)
    let workspace = Workspace(dialogs: dialogs)
    await workspace.open(legacy)
    var expected = try WorkspaceModel.newBlock()
    try expected.pinCurrent(.width)
    try expected.resize(to: .init(dimension: .width, value: 1, unit: .inch), changingPin: true)
    try expected.resize(to: .init(dimension: .height, value: 7, unit: .millimeter))
    let restored = workspace.activeModel!
    precondition(restored.mesh == expected.mesh && restored.unit == expected.unit && restored.pins == expected.pins)
    precondition(!workspace.resize(to: .init(dimension: .width, value: 3, unit: .inch), changingPin: false))
    precondition(workspace.modelError?.contains("Pinned Width (X)") == true && !workspace.hasUnsavedChanges)
    retained(workspace, restored)
    precondition(workspace.resize(to: .init(dimension: .height, value: 8, unit: .millimeter), changingPin: false))
    workspace.pinCurrent(.height)
    let edited = workspace.activeModel!
    workspace.modelError = nil

    // Both actions stop on a canceled save panel or a real filesystem write failure.
    dialogs.choice = .save
    for destination: URL? in [nil, directory.appendingPathComponent("absent/subdirectory/model.studio3d")] {
        dialogs.destination = destination
        dialogs.events.removeAll()
        await workspace.open()
        let quit = await workspace.shouldQuit()
        precondition(!quit && dialogs.events == ["confirm open", "save", "confirm quit", "save"])
        precondition((workspace.modelError != nil) == (destination != nil))
        precondition(workspace.hasUnsavedChanges)
        retained(workspace, edited)
    }
    dialogs.choice = .discard
    dialogs.events.removeAll()
    let discardQuit = await workspace.shouldQuit()
    precondition(discardQuit && dialogs.events == ["confirm quit"])

    let invalidUnit = directory.appendingPathComponent("overflow.obj")
    try "v 0 0 0\nv 1e307 0 0\nv 0 1 0\nf 1 2 3\n".write(to: invalidUnit, atomically: true, encoding: .utf8)
    let missing = directory.appendingPathComponent("missing.studio3d")
    let unsupported = directory.appendingPathComponent("unsupported.studio3d")
    let legacyData = try Data(contentsOf: legacy)
    var archive = try JSONSerialization.jsonObject(with: legacyData) as! [String: Any]
    archive["version"] = 99
    try JSONSerialization.data(withJSONObject: archive).write(to: unsupported)
    for scenario in ["picker canceled", "picker failed", "read failed", "version failed", "units canceled", "units failed"] {
        workspace.modelError = nil
        dialogs.events.removeAll()
        switch scenario {
        case "picker failed": dialogs.source = .failure(MeshImportError("Picker unavailable"))
        case "read failed": dialogs.source = .success(missing)
        case "version failed": dialogs.source = .success(unsupported)
        case "units canceled": dialogs.source = .success(fixtures.appendingPathComponent("block.stl"))
        case "units failed": dialogs.source = .success(invalidUnit)
        default: dialogs.source = .success(nil)
        }
        await workspace.open()
        if scenario.hasPrefix("units") {
            precondition(workspace.pendingUnits != nil)
            let overlappingQuit = await workspace.shouldQuit()
            precondition(!overlappingQuit)
            await workspace.open(legacy)
            workspace.unpin(.height)
            retained(workspace, edited)
            if scenario == "units failed" { workspace.acceptUnit(.meter) }
            else { workspace.pendingUnits = nil }
        }
        retained(workspace, edited)
        precondition(workspace.hasUnsavedChanges && workspace.canStartFileOperation)
        precondition((workspace.modelError != nil) == scenario.hasSuffix("failed"))
        if scenario == "version failed" {
            precondition(workspace.modelError?.contains("Unsupported Model Studio file version 99.") == true)
        }
        precondition(dialogs.events == ["confirm open", "open"])
    }

    let destination = directory.appendingPathComponent("current.studio3d")
    dialogs.destination = destination
    dialogs.choice = .save
    dialogs.events.removeAll()
    dialogs.source = .success(nil)
    dialogs.onPick = {
        let onDisk = try EditableModelFile.read(destination)
        precondition(onDisk.mesh == edited.mesh && onDisk.unit == edited.unit && onDisk.pins == edited.pins)
    }
    await workspace.open() // Save succeeds, then the replacement picker is canceled.
    precondition(dialogs.events == ["confirm open", "save", "open"] && !workspace.hasUnsavedChanges)
    retained(workspace, edited)
    workspace.unpin(.height)
    let savedQuit = await workspace.shouldQuit()
    let quitArchive = try EditableModelFile.read(destination)
    precondition(savedQuit && quitArchive.pins == restored.pins && !workspace.hasUnsavedChanges)
    let lastSave = try Data(contentsOf: destination)
    let reopened = Workspace(dialogs: dialogs)
    await reopened.open(destination)
    precondition(reopened.activeModel?.mesh == edited.mesh && reopened.activeModel?.unit == edited.unit)
    precondition(reopened.resize(to: .init(dimension: .height, value: 9, unit: .millimeter), changingPin: false))
    workspace.pinCurrent(.depth)
    dialogs.choice = .discard
    dialogs.events.removeAll()
    dialogs.onPick = nil
    dialogs.source = .success(fixtures.appendingPathComponent("block.obj"))
    await workspace.open()
    precondition(workspace.activeModel?.id == edited.id)
    workspace.acceptUnit(.inch)
    let afterDiscard = try Data(contentsOf: destination)
    precondition(dialogs.events == ["confirm open", "open"] && afterDiscard == lastSave)
    precondition(workspace.activeModel?.unit == .inch && workspace.activeModel?.id != edited.id && !workspace.hasUnsavedChanges)
    print("Historical v1 fixture, pin enforcement, expired one-time target and Save/Discard/Cancel passed. Picker, read and source-unit failures retained active work.")
}

@MainActor
private func checkStandaloneAssembly(_ directory: URL) async throws {
    let source = directory.appendingPathComponent("source.3mf")
    try FileManager.default.copyItem(at: fixtures.appendingPathComponent("Assemblies/repeated-block.3mf"), to: source)
    let dialogs = ScriptedFileDialogs(choice: .cancel)
    let workspace = Workspace(dialogs: dialogs)
    await workspace.open(source)
    let original = workspace.activeModel!
    let leaf = original.mesh.assembly!.occurrences[1]
    let cap = leaf.importedFaceIDs.lowerBound
    try workspace.applyManualEdit(.extrude([cap]), basedOn: original, distance: 0.5, unit: .millimeter)
    workspace.pinCurrent(.width)
    let edited = workspace.activeModel!
    let archive = directory.appendingPathComponent("assembly.studio3d")
    dialogs.destination = archive
    let saved = await workspace.save()
    precondition(saved)
    try FileManager.default.removeItem(at: source)
    let reopened = Workspace(dialogs: dialogs)
    await reopened.open(archive)
    let model = reopened.activeModel!
    precondition(model.unit == edited.unit && model.mesh == edited.mesh && model.pins == edited.pins)
    let assembly = model.mesh.assembly!
    precondition(assembly.objects == original.mesh.assembly!.objects && assembly.buildItems == original.mesh.assembly!.buildItems)
    let groups = assembly.groupByOccurrence(model.mesh.faces.map(\.id))
    precondition(groups[nil] == nil && groups.count == 3)
    for (index, occurrence) in assembly.occurrences.enumerated() {
        var object = assembly.buildItems[occurrence.buildIndex].object
        for n in occurrence.componentIndices { object = assembly.objects[object]!.components[n].object }
        precondition(object == occurrence.object && assembly.objects[object]!.components.isEmpty)
        if index != 1 { precondition(occurrence == original.mesh.assembly!.occurrences[index]) }
    }
    let wall = original.mesh.nextFaceID
    precondition(groups[1]!.contains(wall))
    let width = model.pins[0]
    let conflictingWidth = DimensionTarget(dimension: width.dimension, value: width.value + 1, unit: width.unit)
    precondition(!reopened.resize(to: conflictingWidth, changingPin: false))
    precondition(reopened.modelError?.contains("Pinned Width (X)") == true && !reopened.hasUnsavedChanges)
    retained(reopened, model)
    try reopened.applyManualEdit(.extrude([wall]), basedOn: reopened.activeModel!, distance: 0.1, unit: .millimeter)
    let nextMesh = reopened.activeModel!.mesh
    precondition(reopened.activeModel!.pins == model.pins)
    precondition(nextMesh.nextFaceID > model.mesh.nextFaceID)
    for face in nextMesh.faces where face.id >= model.mesh.nextFaceID {
        precondition(nextMesh.assembly!.occurrences[1].contains(faceID: face.id))
    }
    print("Edited assembly reopened after source removal with its hierarchy, transforms, occurrences, stable IDs and wall ownership. A conflicting width was rejected, and further wall extrusion passed with the restored pin in force.")
}

let fileCheckDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: fileCheckDirectory, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: fileCheckDirectory) }
try await checkDirtyChanges(fileCheckDirectory)
try await checkInterruptions(fileCheckDirectory)
try await checkStandaloneAssembly(fileCheckDirectory)
