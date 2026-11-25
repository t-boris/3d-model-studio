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
struct MeshFace: Identifiable, Equatable {
    let id: Int
    var vertices: SIMD3<Int>
}

struct EditableMesh: Equatable {
    var vertices: [SIMD3<Double>] = []
    private(set) var faces: [MeshFace] = []
    private var nextFaceID = 0

    mutating func addFace(_ a: Int, _ b: Int, _ c: Int) {
        faces.append(MeshFace(id: nextFaceID, vertices: SIMD3(a, b, c)))
        nextFaceID += 1
    }

    func checked() throws -> Self {
        guard !faces.isEmpty else {
            throw MeshImportError("The file has no mesh faces. Export a surface or solid mesh.")
        }
        guard vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
            throw MeshImportError("A vertex has a non-finite coordinate. Correct the coordinates and export again.")
        }
        return self
    }
}

struct WorkspaceModel: Identifiable {
    let id = UUID()
    var name: String
    var unit: MeshUnit
    var mesh: EditableMesh
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

    func model(in unit: MeshUnit) -> WorkspaceModel {
        WorkspaceModel(name: name, unit: self.unit ?? unit, mesh: mesh)
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
