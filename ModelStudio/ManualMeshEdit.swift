import Foundation
import simd

enum ManualMeshEdit {
    case movePoint(Int, axis: ModelDimension)
    case reshape(Set<Int>, axis: ModelDimension)
    case extrude(Set<Int>)

    func proposal(for model: WorkspaceModel, distance: Double, unit: MeshUnit) throws -> EditableMesh {
        let mm = distance * unit.millimetersPerUnit
        guard mm.isFinite, mm != 0 else {
            throw MeshImportError("Enter a finite, nonzero distance in \(unit.symbol).")
        }
        let mesh = model.mesh
        var result = mesh

        // Check the displacement actually representable at each original point.
        // Subtract first so that a large world coordinate cannot mask a lost edit.
        func displaced(_ index: Int, along direction: SIMD3<Double>) throws -> SIMD3<Double> {
            let start = mesh.vertices[index]
            let end = start + direction * (mm / model.unit.millimetersPerUnit)
            let step = (end - start) * model.unit.millimetersPerUnit
            let measured = simd_dot(step, direction)
            guard end != start, DimensionTarget.matches(measuredMM: measured, targetMM: mm),
                  simd_length(step - direction * measured) <= DimensionTarget.toleranceMM else {
                throw MeshImportError("The requested displacement of \(distance) \(unit.symbol) cannot be represented within ±\(DimensionTarget.toleranceMM) mm at this point.")
            }
            return end
        }

        func translate(_ indices: Set<Int>, along axis: ModelDimension) throws {
            var direction = SIMD3<Double>.zero
            direction[axis.axis] = 1
            for i in indices { result.vertices[i] = try displaced(i, along: direction) }
        }

        switch self {
        case let .movePoint(point, axis):
            guard mesh.vertices.indices.contains(point), mesh.faces.contains(where: {
                $0.vertices.x == point || $0.vertices.y == point || $0.vertices.z == point
            }) else { throw MeshImportError("Select a point on the current surface.") }
            try translate([point], along: axis)

        case let .reshape(selection, axis):
            let faces = try mesh.selectedFaceIndices(selection)
            try translate(mesh.cornerIndices(of: faces), along: axis)

        case let .extrude(selection):
            guard mm > 0 else { throw MeshImportError("Enter a positive extrusion distance.") }
            let faces = try mesh.selectedFaceIndices(selection)
            let patch = try PlanarPatch(mesh: mesh, faces: faces, unit: model.unit)
            guard result.canAppendFaces(2 * patch.boundary.count) else {
                throw MeshImportError("The mesh cannot allocate identifiers for the extrusion walls.")
            }
            // Keep the original corners needed by a wall or an unselected face.
            // Only vertices used exclusively inside the cap can move in place.
            let selectedPoints = mesh.cornerIndices(of: faces)
            var retainOriginal = Set(patch.boundary.map(\.x))
            for face in mesh.faces where !selection.contains(face.id) {
                for corner in 0..<3 where selectedPoints.contains(face.vertices[corner]) {
                    retainOriginal.insert(face.vertices[corner])
                }
            }
            var cap: [Int: Int] = [:]
            for i in selectedPoints.sorted() {
                let position = try displaced(i, along: patch.normal)
                if retainOriginal.contains(i) {
                    cap[i] = result.vertices.count
                    result.vertices.append(position)
                } else {
                    cap[i] = i
                    result.vertices[i] = position
                }
            }
            for i in faces {
                let old = mesh.faces[i].vertices
                result.replaceCorners(at: i, with: SIMD3(cap[old.x]!, cap[old.y]!, cap[old.z]!))
            }
            for edge in patch.boundary {
                result.addFace(edge.x, edge.y, cap[edge.y]!)
                result.addFace(edge.x, cap[edge.y]!, cap[edge.x]!)
            }
        }
        return result
    }
}

private extension EditableMesh {
    func selectedFaceIndices(_ selection: Set<Int>) throws -> [Int] {
        let indices = faces.indices.filter { selection.contains(faces[$0].id) }
        guard !indices.isEmpty, indices.count == selection.count else {
            throw MeshImportError("Select faces on the current surface.")
        }
        return indices
    }

    func cornerIndices(of indices: [Int]) -> Set<Int> {
        var result = Set<Int>()
        for i in indices {
            for corner in 0..<3 { result.insert(faces[i].vertices[corner]) }
        }
        return result
    }
}

private struct PlanarPatch {
    let normal: SIMD3<Double>
    let boundary: [SIMD2<Int>]

    init(mesh: EditableMesh, faces: [Int], unit: MeshUnit) throws {
        let error = MeshImportError("Extrude one triangle or a connected, flat patch with consistent winding and a simple boundary.")
        let origin = mesh.vertices[mesh.faces[faces[0]].vertices.x]
        var firstNormal: SIMD3<Double>?
        var edges: [SIMD2<Int>: [(face: Int, direction: SIMD2<Int>)]] = [:]
        for i in faces {
            let v = mesh.faces[i].vertices
            let a = mesh.vertices[v.x], b = mesh.vertices[v.y], c = mesh.vertices[v.z]
            let n = simd_normalize(simd_cross(simd_normalize(b - a), simd_normalize(c - a)))
            let reference = firstNormal ?? n
            guard simd_dot(n, reference) >= 1 - 1e-10 else { throw error }
            firstNormal = reference
            for j in 0..<3 {
                let from = v[j], to = v[(j + 1) % 3]
                let height = simd_dot(mesh.vertices[from] - origin, reference) * unit.millimetersPerUnit
                guard DimensionTarget.matches(measuredMM: height, targetMM: 0) else { throw error }
                edges[SIMD2(min(from, to), max(from, to)), default: []].append((i, SIMD2(from, to)))
            }
        }

        var neighbors: [Int: [Int]] = [:]
        var rim: [SIMD2<Int>] = []
        for uses in edges.values {
            let first = uses[0]
            if uses.count == 1 {
                rim.append(first.direction)
            } else {
                guard uses.count == 2, first.direction.x == uses[1].direction.y,
                      first.direction.y == uses[1].direction.x else { throw error }
                neighbors[first.face, default: []].append(uses[1].face)
                neighbors[uses[1].face, default: []].append(first.face)
            }
        }
        var visited = Set<Int>()
        var pending = [faces[0]]
        while let i = pending.popLast() {
            if visited.insert(i).inserted { pending += neighbors[i] ?? [] }
        }
        let starts = Set(rim.map(\.x))
        guard visited.count == faces.count, !rim.isEmpty, starts.count == rim.count,
              starts == Set(rim.map(\.y)) else { throw error }
        normal = firstNormal!
        boundary = rim.sorted { $0.x < $1.x }
    }
}
