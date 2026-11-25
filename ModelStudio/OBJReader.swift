import Foundation
import simd

enum OBJReader {
    static func read(_ text: String) throws -> EditableMesh {
        var mesh = EditableMesh()
        var continued = ""
        for (offset, line) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let record = line.prefix { $0 != "#" }.trimmingCharacters(in: .whitespaces)
            if record.hasSuffix("\\") {
                continued += record.dropLast() + " "
                continue
            }
            let fields = (continued + record).split(whereSeparator: \.isWhitespace)
            continued = ""
            switch fields.first {
            case "v":
                let coordinates = fields.dropFirst().prefix(3).compactMap { Double($0) }
                guard coordinates.count == 3, coordinates.allSatisfy(\.isFinite) else {
                    throw MeshImportError("OBJ line \(offset + 1) has an invalid vertex. Enter three finite coordinates.")
                }
                mesh.vertices.append(SIMD3(coordinates[0], coordinates[1], coordinates[2]))
            case "f":
                let corners = try fields.dropFirst().map { field in
                    let position = field.prefix { $0 != "/" }
                    guard let value = Int(position), value != 0 else {
                        throw MeshImportError("OBJ line \(offset + 1) needs a vertex index for each face corner.")
                    }
                    let index = value > 0 ? value - 1 : mesh.vertices.count + value
                    guard mesh.vertices.indices.contains(index) else {
                        throw MeshImportError("OBJ line \(offset + 1) refers to a missing vertex. Check the face indices.")
                    }
                    return index
                }
                try triangulate(corners, line: offset + 1, mesh: &mesh)
            case "curv", "curv2", "surf", "p", "l", "call":
                throw MeshImportError("OBJ line \(offset + 1) contains non-mesh geometry. Convert it to mesh faces and export again.")
            default:
                continue // Texture, normal, group and material records do not define mesh connectivity.
            }
        }
        guard continued.isEmpty else { throw MeshImportError("The OBJ ends mid-record. Export the complete file.") }
        return mesh
    }

    // Clip ears in the polygon's dominant projection, preserving winding and shared indices.
    private static func triangulate(_ corners: [Int], line: Int, mesh: inout EditableMesh) throws {
        let error = MeshImportError("Cannot triangulate the face on OBJ line \(line). Export it as simple triangles.")
        guard corners.count >= 3 else { throw error }
        if corners.count == 3 {
            mesh.addFace(corners[0], corners[1], corners[2])
            return
        }
        let origin = mesh.vertices[corners[0]]
        let points = corners.map { mesh.vertices[$0] - origin }
        var normal = SIMD3<Double>.zero
        for i in points.indices {
            normal += simd_cross(points[i], points[(i + 1) % points.count])
        }
        let axis = (0..<3).max { abs(normal[$0]) < abs(normal[$1]) }!
        guard normal[axis].isFinite, normal[axis] != 0 else { throw error }
        let winding = normal[axis] > 0 ? 1.0 : -1.0
        let projected = points.map { SIMD2($0[(axis + 1) % 3], $0[(axis + 2) % 3]) }
        func turn(_ a: Int, _ b: Int, _ c: Int) -> Double {
            let u = projected[b] - projected[a]
            let v = projected[c] - projected[a]
            return (u.x * v.y - u.y * v.x) * winding
        }

        var ring = Array(corners.indices)
        while ring.count > 3 {
            var clipped = false
            for i in ring.indices {
                let a = ring[(i + ring.count - 1) % ring.count]
                let b = ring[i]
                let c = ring[(i + 1) % ring.count]
                guard turn(a, b, c) > 0 else { continue }
                let containsPoint = ring.contains { p in
                    p != a && p != b && p != c && turn(a, b, p) >= 0 && turn(b, c, p) >= 0 && turn(c, a, p) >= 0
                }
                if !containsPoint {
                    mesh.addFace(corners[a], corners[b], corners[c])
                    ring.remove(at: i)
                    clipped = true
                    break
                }
            }
            guard clipped else { throw error }
        }
        mesh.addFace(corners[ring[0]], corners[ring[1]], corners[ring[2]])
    }
}
