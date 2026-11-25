import Foundation
import simd

enum MeshUnit: String, CaseIterable, Codable {
    case micron, millimeter, centimeter, meter, inch, foot

    var symbol: String {
        switch self {
        case .micron: "µm"
        case .millimeter: "mm"
        case .centimeter: "cm"
        case .meter: "m"
        case .inch: "in"
        case .foot: "ft"
        }
    }

    var millimetersPerUnit: Double {
        switch self {
        case .micron: 0.001
        case .millimeter: 1
        case .centimeter: 10
        case .meter: 1000
        case .inch: 25.4
        case .foot: 304.8
        }
    }
}

// Positions are expressed in the active model's unit. Incident triangles reference
// the same vertex index. Face IDs survive vertex movement and face array reordering.
struct MeshFace: Identifiable, Equatable, Codable {
    let id: Int
    var vertices: SIMD3<Int>
}

struct EditableMesh: Equatable, Codable {
    var vertices: [SIMD3<Double>] = []
    private(set) var faces: [MeshFace] = []
    private var nextFaceID = 0

    mutating func addFace(_ a: Int, _ b: Int, _ c: Int) {
        faces.append(MeshFace(id: nextFaceID, vertices: SIMD3(a, b, c)))
        nextFaceID += 1
    }

    mutating func replaceCorners(at index: Int, with corners: SIMD3<Int>) {
        faces[index].vertices = corners
    }

    func canAppendFaces(_ count: Int) -> Bool {
        count < Int.max - nextFaceID
    }

    func checked() throws -> Self {
        guard !faces.isEmpty else {
            throw MeshImportError("The file has no mesh faces. Export a surface or solid mesh.")
        }
        guard vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
            throw MeshImportError("A vertex has a non-finite coordinate. Correct the coordinates and export again.")
        }
        var ids = Set<Int>()
        for face in faces {
            let corners = face.vertices
            guard vertices.indices.contains(corners.x), vertices.indices.contains(corners.y),
                  vertices.indices.contains(corners.z) else {
                throw MeshImportError("A face references a missing vertex.")
            }
            guard face.id >= 0, face.id < nextFaceID, nextFaceID < Int.max,
                  ids.insert(face.id).inserted else {
                throw MeshImportError("The mesh contains invalid face identifiers.")
            }
        }
        return self
    }

    // Operate on the indexed surface. OBJ files can also contain unused vertices.
    var surfaceBounds: (low: SIMD3<Double>, high: SIMD3<Double>) {
        var low = SIMD3<Double>(repeating: .infinity)
        var high = -low
        for face in faces {
            for corner in 0..<3 {
                let point = vertices[face.vertices[corner]]
                low = simd_min(low, point)
                high = simd_max(high, point)
            }
        }
        return (low, high)
    }
}

struct MeshImportError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

// A unitless import cannot become a workspace model until its unit has been chosen.
struct MeshImport: Identifiable {
    let id = UUID()
    let name: String
    let mesh: EditableMesh
    let unit: MeshUnit?

    func model(in unit: MeshUnit) throws -> WorkspaceModel {
        try WorkspaceModel(name: name, unit: self.unit ?? unit, mesh: mesh)
    }

    static func read(_ url: URL) throws -> Self {
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        let mesh: EditableMesh
        var unit: MeshUnit?
        switch url.pathExtension.lowercased() {
        case "stl":
            mesh = try STLReader.read(Data(contentsOf: url, options: .mappedIfSafe))
        case "obj":
            mesh = try OBJReader.read(String(contentsOf: url, encoding: .utf8))
        case "3mf":
            (mesh, unit) = try ThreeMFReader.read(url)
        default:
            throw MeshImportError("Choose an STL, OBJ, or 3MF mesh file.")
        }
        return try Self(name: url.lastPathComponent, mesh: mesh.checked(), unit: unit)
    }
}
