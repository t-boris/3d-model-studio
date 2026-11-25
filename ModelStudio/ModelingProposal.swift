import Foundation
import simd

struct ModelingProposal {
    let original: WorkspaceModel?
    let preview: WorkspaceModel
    let requested: [DimensionTarget]

    init(operation: ModelingOperation, patch: AgentMeshPatch) throws {
        guard operation.scope.target == nil else {
            throw MeshImportError("A selection edit requires affected-face review.")
        }
        guard let constraints = patch.unsupportedConstraints, let dimensions = patch.requestedDimensions else {
            throw MeshImportError("The provider omitted its dimensional assessment. Request a new proposal.")
        }
        guard constraints.isEmpty else {
            throw MeshImportError("Unsupported dimensional constraints: " + constraints.joined(separator: ", "))
        }
        let input = try operation.input()
        original = operation.scope.model
        requested = try ConversationDimensions.targets(input: input, interpreted: dimensions, original: original)
        let mesh = try patch.applying(to: original?.mesh ?? EditableMesh(), visible: input)
        if var model = original {
            try model.commit(mesh, requested: requested)
            preview = model
        } else {
            preview = try WorkspaceModel(name: "Untitled Model", unit: input.unit, mesh: mesh, requested: requested)
        }
    }

    @MainActor
    func apply(to workspace: Workspace) throws {
        if let original {
            try workspace.commit(preview.mesh, basedOn: original, requested: requested)
        } else {
            try workspace.commitCreation(preview.mesh, unit: preview.unit, requested: requested)
        }
    }
}

private extension AgentMeshPatch {
    func applying(to original: EditableMesh, visible: ModelingInput) throws -> EditableMesh {
        let knownVertices = Set(visible.vertices.map(\.id))
        let knownFaces = Set(visible.faces.map(\.id))
        let removed = Set(removedFaceIDs)
        guard removed.count == removedFaceIDs.count, removed.isSubset(of: knownFaces) else {
            throw MeshImportError("The proposal removes an unknown or repeated face.")
        }
        let changedFaces = Set(faces.map(\.id))
        guard changedFaces.count == faces.count, removed.isDisjoint(with: changedFaces),
              faces.allSatisfy({ $0.id < 0 || knownFaces.contains($0.id) }) else {
            throw MeshImportError("The proposal contains conflicting or unknown face IDs.")
        }
        guard Set(vertices.map(\.id)).count == vertices.count else {
            throw MeshImportError("The proposal repeats a vertex ID.")
        }

        var mesh = original
        var added: [Int: Int] = [:]
        var moved = Set<Int>()
        for vertex in vertices {
            if vertex.id < 0 {
                added[vertex.id] = mesh.vertices.count
                mesh.vertices.append(vertex.position)
            } else {
                guard knownVertices.contains(vertex.id) else { throw MeshImportError("Unknown vertex ID \(vertex.id).") }
                if mesh.vertices[vertex.id] != vertex.position { moved.insert(vertex.id) }
                mesh.vertices[vertex.id] = vertex.position
            }
        }

        mesh.removeFaces(withIDs: removed)
        let existing = Dictionary(uniqueKeysWithValues: mesh.faces.enumerated().map { ($0.element.id, $0.offset) })
        guard mesh.canAppendFaces(faces.filter { $0.id < 0 }.count) else {
            throw MeshImportError("There are too many faces in this proposal.")
        }
        var usedNew = Set<Int>()
        var changed = Set<Int>()
        for face in faces {
            var corners = face.vertices
            for i in 0..<3 {
                let id = corners[i]
                if let index = added[id] {
                    corners[i] = index
                    usedNew.insert(id)
                } else if !knownVertices.contains(id) {
                    throw MeshImportError("Face \(face.id) refers to unknown vertex \(id).")
                }
            }
            if let index = existing[face.id] {
                if mesh.faces[index].vertices != corners { changed.insert(face.id) }
                mesh.replaceCorners(at: index, with: corners)
            } else {
                mesh.addFace(corners.x, corners.y, corners.z)
                changed.insert(mesh.faces[mesh.faces.count - 1].id)
            }
        }
        guard usedNew.count == added.count else { throw MeshImportError("A new vertex has no incident face.") }
        var surfaceChanged = !removed.isEmpty
        for face in mesh.faces {
            let v = face.vertices
            guard changed.contains(face.id) || moved.contains(v.x) || moved.contains(v.y) || moved.contains(v.z) else { continue }
            let normal = simd_cross(mesh.vertices[v.y] - mesh.vertices[v.x], mesh.vertices[v.z] - mesh.vertices[v.x])
            guard normal != .zero, normal.x.isFinite, normal.y.isFinite, normal.z.isFinite else {
                throw MeshImportError("The proposal collapses face \(face.id) or exceeds the supported coordinate range.")
            }
            surfaceChanged = true
        }
        guard surfaceChanged else { throw MeshImportError("The proposal makes no surface change.") }
        return mesh
    }
}
