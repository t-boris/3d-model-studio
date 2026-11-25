import Foundation

func rejected(_ fragment: String, _ edit: () throws -> Void) {
    do {
        try edit()
        fatalError("Accepted a proposal expected to fail: \(fragment)")
    } catch {
        precondition(error.localizedDescription.contains(fragment), error.localizedDescription)
    }
}

func target(_ dimension: ModelDimension, _ value: Double, _ unit: MeshUnit = .millimeter) -> DimensionTarget {
    DimensionTarget(dimension: dimension, value: value, unit: unit)
}

func checkTolerance() throws {
    var block = try WorkspaceModel.newBlock()
    try block.pinCurrent(.width)
    try block.pinCurrent(.depth)
    let original = block.mesh
    for (value, accepted) in [(9.9899, false), (9.99, true), (10.01, true), (10.0101, false)] {
        var proposal = original
        for i in proposal.vertices.indices where proposal.vertices[i].y == 10 {
            proposal.vertices[i].y = value
        }
        var pinned = block
        var once = try WorkspaceModel.newBlock()
        if accepted {
            try pinned.commit(proposal)
            try once.commit(proposal, requested: [target(.depth, 1, .centimeter)])
        } else {
            rejected("Pinned Depth (Y)") { try pinned.commit(proposal) }
            rejected("Requested Depth (Y)") {
                try once.commit(proposal, requested: [target(.height, 10), target(.depth, 1, .centimeter)])
            }
            precondition(pinned.mesh == original && pinned.pins == block.pins)
            precondition(once.mesh == original && once.pins.isEmpty)
        }
    }

    for unit in MeshUnit.allCases {
        try block.commit(original, requested: [target(.width, 10 / unit.millimetersPerUnit, unit)])
    }
    for invalid in [Double.nan, .infinity, -1] {
        rejected("Width (X)") { try block.resize(to: target(.width, invalid), changingPin: true) }
        precondition(block.mesh == original && block.pins[0] == target(.width, 10))
    }
    var unused = original
    unused.vertices.append(SIMD3(repeating: 1000))
    try block.commit(unused)
    precondition(block.extents == SIMD3(repeating: 10))
    try block.resize(to: target(.height, 0))
    let flat = block.mesh
    rejected("Requested Height (Z)") { try block.resize(to: target(.height, 5)) }
    precondition(block.mesh == flat)
}

@MainActor
func checkReopen(source: String?, directory: URL) async throws {
    let workspace = Workspace()
    if let source {
        await workspace.open(URL(fileURLWithPath: "Fixtures/Import/block." + source))
        if source != "3mf" { workspace.acceptUnit(.millimeter) }
    } else {
        workspace.newBlock()
    }
    let original = workspace.activeModel!
    precondition(workspace.modelError == nil)
    workspace.pinCurrent(.width)
    workspace.pinCurrent(.depth)
    precondition(workspace.resize(to: target(.width, 1, .inch), changingPin: true))
    precondition(workspace.resize(to: target(.height, 7), changingPin: false))
    let edited = workspace.activeModel!
    precondition(edited.mesh != original.mesh && edited.mesh.faces == original.mesh.faces)
    precondition(edited.pins.count == 2 && edited.pins[0] == target(.width, 1, .inch))
    precondition(abs(edited.extents.z * edited.unit.millimetersPerUnit - 7) < 1e-12)
    let saved = directory.appendingPathComponent("edited.studio3d")
    let bytes = try EditableModelFile(model: edited).encoded()
    try bytes.write(to: saved, options: .atomic)
    let reopened = Workspace()
    await reopened.open(saved)
    let restored = reopened.activeModel!
    precondition(restored.mesh == edited.mesh && restored.pins == edited.pins && restored.unit == edited.unit)
    precondition(!reopened.resize(to: target(.width, 2, .inch), changingPin: false))
    precondition(reopened.modelError?.contains("Pinned Width (X)") == true)
    precondition(restored.mesh == reopened.activeModel!.mesh && restored.pins == reopened.activeModel!.pins)
    precondition(reopened.resize(to: target(.height, 9), changingPin: false))
    precondition(reopened.activeModel!.pins == edited.pins)
    rejected("model changed") { try reopened.commit(restored.mesh, basedOn: restored) }

    let snapshot = reopened.activeModel!
    reopened.pinCurrent(.height)
    rejected("Pinned Height (Z)") { try reopened.commit(restored.mesh, basedOn: snapshot) }
    reopened.unpin(.height)
    try reopened.commit(restored.mesh, basedOn: snapshot, requested: [target(.height, 7)])
    reopened.unpin(.width)
    precondition(reopened.resize(to: target(.width, 2, .inch), changingPin: false))
    precondition(reopened.activeModel!.pins.map(\.dimension) == [.depth])

    // Opening a damaged archive must preserve the current model, including its identity.
    let retained = reopened.activeModel!
    let archive = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
    for corruption in ["version", "pin", "index", "duplicate pin", "truncated"] {
        var broken = archive
        switch corruption {
        case "version": broken["version"] = 90
        case "pin", "duplicate pin":
            var pins = broken["pins"] as! [[String: Any]]
            if corruption == "pin" { pins[0]["value"] = 1000 }
            else { pins.append(pins[0]) }
            broken["pins"] = pins
        case "index":
            var mesh = broken["mesh"] as! [String: Any]
            var faces = mesh["faces"] as! [[String: Any]]
            faces[0]["vertices"] = [0, -1, 2]
            mesh["faces"] = faces
            broken["mesh"] = mesh
        default: break
        }
        let damaged = try corruption == "truncated" ? Data(bytes.prefix(12)) : JSONSerialization.data(withJSONObject: broken)
        try damaged.write(to: saved, options: .atomic)
        reopened.modelError = nil
        await reopened.open(saved)
        precondition(reopened.modelError != nil)
        precondition(reopened.activeModel!.id == retained.id && reopened.activeModel!.mesh == retained.mesh)
        precondition(reopened.activeModel!.pins == retained.pins && reopened.activeModel!.unit == retained.unit)
    }
    print("Round trip, continued editing and failed open passed for \(source ?? "new block").")
}

try checkTolerance()
print("Tolerance limits, six units, flat spans and atomic rejection passed.")
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: directory) }
for source: String? in [nil, "stl", "obj", "3mf"] {
    try await checkReopen(source: source, directory: directory)
}
