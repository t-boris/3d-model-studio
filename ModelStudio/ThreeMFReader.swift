import Foundation
import simd

enum ThreeMFReader {
    private static let core = "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"
    private static let modelRelation = "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"

    static func read(_ url: URL) throws -> (EditableMesh, MeshUnit) {
        let relationships = try xmlPart("_rels/.rels", from: url, limit: 1024 * 1024)
        let links = relationships.elements(forLocalName: "Relationship",
                                          uri: "http://schemas.openxmlformats.org/package/2006/relationships")
        let start = links.filter { $0.value("Type") == modelRelation }
        guard start.count == 1, start[0].value("TargetMode") != "External",
              let target = start[0].value("Target")?.removingPercentEncoding else {
            throw MeshImportError("The 3MF package needs one internal start model. Re-export it as Core 3MF.")
        }
        let path = target.hasPrefix("/") ? String(target.dropFirst()) : target
        let segments = path.components(separatedBy: "/")
        guard !segments.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              !path.hasPrefix("-"), path.rangeOfCharacter(from: CharacterSet(charactersIn: "*?[]\\")
                .union(.controlCharacters)) == nil else {
            throw MeshImportError("The 3MF start model has an unsupported part name. Re-export it with a simple model path.")
        }
        let root = try xmlPart(path, from: url, limit: 128 * 1024 * 1024)
        guard root.localName == "model", root.uri == core else {
            throw MeshImportError("The start part is not a Core 3MF model. Export a Core 3MF triangle mesh.")
        }
        guard (root.value("requiredextensions") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshImportError("This 3MF requires an extension. Export a flattened Core 3MF mesh.")
        }
        guard let unit = MeshUnit(rawValue: root.value("unit") ?? "millimeter") else {
            throw MeshImportError("The 3MF model unit is unknown. Export with a standard 3MF length unit.")
        }

        let resources = try child("resources", of: root)
        var objects: [Int: XMLElement] = [:]
        for object in children("object", of: resources) {
            let id = try object.integer("id")
            guard id > 0, objects.updateValue(object, forKey: id) == nil else {
                throw MeshImportError("3MF object IDs must be positive and unique. Repair the object list.")
            }
        }

        var assembly = Assembly(objects: objects)
        for item in children("item", of: try child("build", of: root)) {
            try assembly.append(item, parent: matrix_identity_double4x4, ancestors: [])
        }
        return (assembly.mesh, unit)
    }

    private struct Assembly {
        let objects: [Int: XMLElement]
        var mesh = EditableMesh()
        var instances = 0

        mutating func append(_ reference: XMLElement, parent: simd_double4x4, ancestors: Set<Int>) throws {
            let id = try reference.integer("objectid")
            guard let object = objects[id], !ancestors.contains(id) else {
                throw MeshImportError("3MF object \(id) is missing or references itself. Repair or flatten the assembly.")
            }
            instances += 1
            guard ancestors.count < 128, instances <= 100_000 else {
                throw MeshImportError("The 3MF assembly is too complex. Export a smaller, flattened assembly.")
            }
            guard reference.attributes?.contains(where: { $0.localName == "path" }) != true else {
                throw MeshImportError("This assembly references another model part. Export it as a single Core 3MF model.")
            }
            let world = try parent * transform(reference.value("transform"))
            if let components = children("components", of: object).first {
                guard children("mesh", of: object).isEmpty else {
                    throw MeshImportError("3MF object \(id) has both a mesh and components. Re-export the assembly.")
                }
                let parts = children("component", of: components)
                guard !parts.isEmpty else { throw MeshImportError("3MF object \(id) has no components. Repair the assembly.") }
                for part in parts {
                    try append(part, parent: world, ancestors: ancestors.union([id]))
                }
            } else {
                try appendMesh(child("mesh", of: object), transform: world)
            }
        }

        mutating func appendMesh(_ element: XMLElement, transform: simd_double4x4) throws {
            let base = mesh.vertices.count
            let vertices = children("vertex", of: try child("vertices", of: element))
            let triangles = children("triangle", of: try child("triangles", of: element))
            guard !vertices.isEmpty, !triangles.isEmpty else {
                throw MeshImportError("A 3MF object has an empty mesh. Re-export with vertices and triangles.")
            }
            guard base + vertices.count <= 5_000_000, mesh.faces.count + triangles.count <= 5_000_000 else {
                throw MeshImportError("The expanded 3MF exceeds five million vertices or faces. Simplify the assembly.")
            }
            for vertex in vertices {
                let local = try SIMD4(vertex.number("x"), vertex.number("y"), vertex.number("z"), 1)
                let point = transform * local
                mesh.vertices.append(SIMD3(point.x, point.y, point.z))
            }

            let reflected = simd_determinant(transform) < 0
            for triangle in triangles {
                let a = try triangle.integer("v1")
                let b = try triangle.integer("v2")
                let c = try triangle.integer("v3")
                guard vertices.indices.contains(a), vertices.indices.contains(b), vertices.indices.contains(c) else {
                    throw MeshImportError("A 3MF triangle references a missing vertex. Repair the source mesh.")
                }
                mesh.addFace(base + a, base + (reflected ? c : b), base + (reflected ? b : c))
            }
        }
    }

    private static func transform(_ raw: String?) throws -> simd_double4x4 {
        guard let raw else { return matrix_identity_double4x4 }
        let values = raw.split(whereSeparator: \.isWhitespace).map { Double($0) }
        guard values.count == 12, values.allSatisfy({ $0?.isFinite == true }) else {
            throw MeshImportError("A 3MF transform needs 12 finite numbers. Correct it or export with transforms applied.")
        }
        let m = values.compactMap { $0 }
        // Transpose the file's row-vector matrix to SIMD column-vector convention.
        return simd_double4x4(columns: (SIMD4(m[0], m[1], m[2], 0), SIMD4(m[3], m[4], m[5], 0),
                                        SIMD4(m[6], m[7], m[8], 0), SIMD4(m[9], m[10], m[11], 1)))
    }

    private static func children(_ name: String, of parent: XMLElement) -> [XMLElement] {
        parent.elements(forLocalName: name, uri: core)
    }

    private static func child(_ name: String, of parent: XMLElement) throws -> XMLElement {
        let matches = children(name, of: parent)
        guard matches.count == 1 else {
            throw MeshImportError("The 3MF needs one \(name) section here. Re-export a complete Core 3MF model.")
        }
        return matches[0]
    }

    // Read only the requested package part to stdout. No archive member is written to disk.
    private static func xmlPart(_ path: String, from url: URL, limit: Int) throws -> XMLElement {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, path]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardOutput = pipe
        try process.run()
        defer {
            try? pipe.fileHandleForReading.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }

        var data = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            guard data.count + chunk.count <= limit else {
                throw MeshImportError("The 3MF part \(path) is too large. Export a smaller mesh.")
            }
            data.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else {
            throw MeshImportError("Cannot read \(path) from the 3MF package. Re-export the complete, unencrypted file.")
        }
        do {
            let document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
            guard document.dtd == nil, let root = document.rootElement() else {
                throw MeshImportError("Invalid 3MF XML.")
            }
            return root
        } catch {
            throw MeshImportError("Cannot read the XML in \(path). Repair the package or re-export it as Core 3MF.")
        }
    }
}

private extension XMLElement {
    func value(_ name: String) -> String? { attribute(forName: name)?.stringValue }

    func integer(_ name: String) throws -> Int {
        guard let text = value(name), let n = Int(text) else {
            throw MeshImportError("Invalid 3MF \(name) index. Check the referenced objects and vertices.")
        }
        return n
    }

    func number(_ name: String) throws -> Double {
        guard let text = value(name), let n = Double(text), n.isFinite else {
            throw MeshImportError("Invalid 3MF \(name) coordinate. Export with finite vertex coordinates.")
        }
        return n
    }
}
