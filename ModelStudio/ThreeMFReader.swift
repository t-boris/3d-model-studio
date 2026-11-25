import Foundation
import simd

// Source identities are scoped to a package part. Build and component array
// indices are the ordering in the source XML, including repeated references.
struct ThreeMFAssembly: Codable, Equatable {
    struct ObjectID: Codable, Hashable {
        let part: String
        let id: Int
    }

    struct Reference: Codable, Equatable {
        let object: ObjectID
        let transform: ThreeMFTransform
        let uuid: String?
    }

    struct Object: Codable, Equatable {
        let name: String?
        let unit: MeshUnit
        let components: [Reference]
    }

    struct Occurrence: Codable, Equatable {
        let object: ObjectID
        let buildIndex: Int
        let componentIndices: [Int]
        // Original source vertex/triangle order maps directly into these ranges.
        // Face IDs remain meaningful after array reordering or face removal.
        let importedVertices: Range<Int>
        let importedFaceIDs: Range<Int>
        // Older archives omit this field. Current face corners give the vertex
        // indices for an edited occurrence, including any new cap vertices.
        var addedFaceIDRanges: [Range<Int>]? = nil

        func contains(faceID: Int) -> Bool {
            importedFaceIDs.contains(faceID) || addedFaceIDRanges?.contains { $0.contains(faceID) } == true
        }
    }

    let startPart: String
    let buildItems: [Reference]
    var objects: [ObjectID: Object] = [:]
    var occurrences: [Occurrence] = []

    mutating func recordExtrusion(capFaceIDs: Set<Int>, wallFaceIDs: Range<Int>) throws {
        guard let first = capFaceIDs.first,
              let index = occurrences.firstIndex(where: { $0.contains(faceID: first) }),
              capFaceIDs.allSatisfy(occurrences[index].contains(faceID:)) else {
            throw MeshImportError("Extrude faces belonging to one 3MF assembly occurrence.")
        }
        var ranges = occurrences[index].addedFaceIDRanges ?? []
        ranges.append(wallFaceIDs)
        occurrences[index].addedFaceIDRanges = ranges
    }

    // Existing face IDs anchor each occurrence, including replacement triangles
    // and walls from earlier edits. New triangles inherit ownership through
    // shared vertex IDs. Coordinate equality cannot identify a repeated part.
    mutating func recordPatch(original: EditableMesh, candidate: EditableMesh, changedFaces: Set<Int>,
                              selectedFaces: [Int]?) throws {
        guard !changedFaces.isEmpty else { return }
        let ranges = occurrences.indices.flatMap { i in
            ([occurrences[i].importedFaceIDs] + (occurrences[i].addedFaceIDRanges ?? [])).map { ($0, i) }
        }.sorted { $0.0.lowerBound < $1.0.lowerBound }

        func owner(of face: Int) throws -> Int {
            var lo = 0, hi = ranges.count
            while lo < hi {
                let mid = lo + (hi - lo) / 2
                if ranges[mid].0.upperBound <= face { lo = mid + 1 } else { hi = mid }
            }
            guard lo < ranges.count, ranges[lo].0.contains(face) else {
                throw MeshImportError("A changed face has no 3MF occurrence mapping.")
            }
            return ranges[lo].1
        }

        let changed = candidate.faces.filter { changedFaces.contains($0.id) }
        let vertices = Set(changed.flatMap { [$0.vertices.x, $0.vertices.y, $0.vertices.z] })
        var anchors: [Int: Int] = [:]
        func anchor(_ vertex: Int, to occurrence: Int) throws {
            if let prior = anchors[vertex], prior != occurrence {
                throw MeshImportError("The proposal joins vertices from different 3MF occurrences.")
            }
            anchors[vertex] = occurrence
        }
        for face in original.faces {
            let corners = face.vertices
            for i in 0..<3 where vertices.contains(corners[i]) {
                try anchor(corners[i], to: owner(of: face.id))
            }
        }
        var incident: [Int: [Int]] = [:]
        let added = changed.filter { $0.id >= original.nextFaceID }
        for face in changed where face.id < original.nextFaceID {
            let index = try owner(of: face.id)
            for i in 0..<3 { try anchor(face.vertices[i], to: index) }
        }
        for (index, face) in added.enumerated() {
            for i in 0..<3 { incident[face.vertices[i], default: []].append(index) }
        }

        let fallback = try Set((selectedFaces ?? []).map(owner))
        var visited = Set<Int>()
        var additions: [Int: [Int]] = [:]
        for start in added.indices where visited.insert(start).inserted {
            var component = [start]
            var owners = Set<Int>()
            var cursor = 0
            while cursor < component.count {
                let face = added[component[cursor]]
                cursor += 1
                for i in 0..<3 {
                    let vertex = face.vertices[i]
                    if let index = anchors[vertex] { owners.insert(index) }
                    for neighbor in incident.removeValue(forKey: vertex) ?? [] where visited.insert(neighbor).inserted {
                        component.append(neighbor)
                    }
                }
            }
            if owners.isEmpty { owners = occurrences.count == 1 ? [0] : fallback }
            guard owners.count == 1, let index = owners.first else {
                throw MeshImportError("The added surface needs one identifiable 3MF occurrence. Select faces on its intended part.")
            }
            additions[index, default: []].append(contentsOf: component.map { added[$0].id })
        }
        for (index, ids) in additions {
            var ranges = occurrences[index].addedFaceIDRanges ?? []
            for id in ids.sorted() {
                if let last = ranges.last, last.upperBound == id {
                    ranges[ranges.count - 1] = last.lowerBound..<(id + 1)
                } else {
                    ranges.append(id..<(id + 1))
                }
            }
            occurrences[index].addedFaceIDRanges = ranges
        }
    }

}

// 3MF stores three basis vectors followed by the origin. Translation is
// expressed in the referencing part's unit.
struct ThreeMFTransform: Codable, Equatable {
    let x, y, z, origin: SIMD3<Double>

    init(_ raw: String?) throws {
        if let raw {
            let tokens = raw.split(whereSeparator: \.isWhitespace)
            let numbers = tokens.compactMap { Double($0) }
            guard tokens.count == 12, numbers.count == 12, numbers.allSatisfy(\.isFinite) else {
                throw MeshImportError("A 3MF transform needs 12 finite numbers.")
            }
            x = SIMD3(numbers[0], numbers[1], numbers[2])
            y = SIMD3(numbers[3], numbers[4], numbers[5])
            z = SIMD3(numbers[6], numbers[7], numbers[8])
            origin = SIMD3(numbers[9], numbers[10], numbers[11])
        } else {
            x = [1, 0, 0]
            y = [0, 1, 0]
            z = [0, 0, 1]
            origin = .zero
        }
    }

    func matrix(from child: MeshUnit, to parent: MeshUnit) -> simd_double4x4 {
        let scale = child.millimetersPerUnit / parent.millimetersPerUnit
        return simd_double4x4(columns: (SIMD4(x * scale, 0), SIMD4(y * scale, 0),
                                        SIMD4(z * scale, 0), SIMD4(origin, 1)))
    }
}

enum ThreeMFReader {
    private static let core = "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"
    private static let production = "http://schemas.microsoft.com/3dmanufacturing/production/2015/06"
    private static let modelRelation = "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"
    private static let relationships = "http://schemas.openxmlformats.org/package/2006/relationships"

    static func read(_ url: URL) throws -> (EditableMesh, MeshUnit) {
        let starts = try modelTargets("_rels/.rels", in: url, relativeTo: [])
        guard starts.count == 1 else {
            throw MeshImportError("The 3MF package needs one internal start model.")
        }
        let path = starts[0]
        let root = try ModelPart(path: path, url: url, isStart: true)
        let items = try children("item", of: child("build", of: root.element)).map {
            try reference($0, in: path, isStart: true)
        }
        var expansion = Expansion(url: url, root: root,
                                  assembly: ThreeMFAssembly(startPart: path, buildItems: items))
        expansion.partCache.totalCostLimit = 128 * 1024 * 1024
        for (index, item) in items.enumerated() {
            try expansion.append(item, parent: matrix_identity_double4x4, parentUnit: root.unit,
                                 build: index, components: [], ancestors: [])
        }
        expansion.mesh.assembly = expansion.assembly
        return (expansion.mesh, root.unit)
    }

    private static func modelTargets(_ rels: String, in url: URL, relativeTo directory: [String]) throws -> [String] {
        let (root, _) = try xmlPart(rels, from: url, limit: 1024 * 1024)
        guard root.localName == "Relationships", root.uri == relationships else {
            throw MeshImportError("Invalid 3MF relationships part \(rels).")
        }
        return try root.elements(forLocalName: "Relationship", uri: relationships)
            .filter { $0.value("Type") == modelRelation }.map {
                guard ($0.value("TargetMode") ?? "Internal") == "Internal" else {
                    throw MeshImportError("External 3MF model relationship in \(rels). All model parts must be inside the package.")
                }
                return try packagePath($0.value("Target") ?? "", relativeTo: directory)
            }
    }

    // Resolve only package member names. Never pass a URL, option, wildcard,
    // encoded separator or ambiguous traversal component to unzip.
    private static func packagePath(_ raw: String, relativeTo directory: [String]) throws -> String {
        let absolute = raw.hasPrefix("/")
        let path = absolute ? String(raw.dropFirst()) : raw
        let forbidden = CharacterSet(charactersIn: ":*?[]\\#/%").union(.controlCharacters)
        var components = absolute ? [] : directory
        for component in path.components(separatedBy: "/") {
            guard let decoded = component.removingPercentEncoding, !decoded.isEmpty,
                  decoded.rangeOfCharacter(from: forbidden) == nil else {
                throw MeshImportError("Invalid or external 3MF model-part path: \(raw).")
            }
            if decoded == "." || decoded == ".." {
                // OPC relationships may use relative directory navigation.
                guard !absolute, component == decoded else {
                    throw MeshImportError("Invalid 3MF model-part path: \(raw).")
                }
                if decoded == ".." {
                    guard !components.isEmpty else { throw MeshImportError("3MF path escapes the package: \(raw).") }
                    components.removeLast()
                }
            } else {
                components.append(decoded)
            }
        }
        let member = components.joined(separator: "/")
        guard !member.isEmpty, !member.hasPrefix("-") else {
            throw MeshImportError("Invalid 3MF model-part path: \(raw).")
        }
        return member
    }

    private static func reference(_ element: XMLElement, in part: String, isStart: Bool) throws -> ThreeMFAssembly.Reference {
        var target = part
        let paths = element.attributes?.filter { $0.localName == "path" } ?? []
        if let path = paths.first {
            guard paths.count == 1, path.uri == production, isStart,
                  let raw = path.stringValue, raw.hasPrefix("/") else {
                throw MeshImportError("Invalid or external 3MF part reference in \(part). Use a Production path from the package root.")
            }
            target = try packagePath(raw, relativeTo: [])
            guard target != part else { throw MeshImportError("Cyclic model-part reference to \(part).") }
        }
        let id = try element.integer("objectid")
        guard id > 0 else { throw MeshImportError("Invalid 3MF object reference \(id) in \(part).") }
        return try .init(object: .init(part: target, id: id), transform: ThreeMFTransform(element.value("transform")),
                         uuid: element.attribute(forLocalName: "UUID", uri: production)?.stringValue)
    }

    private final class ModelPart {
        let element: XMLElement
        let unit: MeshUnit
        let objects: [Int: XMLElement]
        let byteCount: Int

        init(path: String, url: URL, isStart: Bool) throws {
            let (root, bytes) = try xmlPart(path, from: url, limit: 128 * 1024 * 1024)
            byteCount = bytes
            guard root.localName == "model", root.uri == core else {
                throw MeshImportError("Invalid model part \(path): expected a Core 3MF model.")
            }
            for prefix in (root.value("requiredextensions") ?? "").split(whereSeparator: \.isWhitespace) {
                guard root.namespace(forPrefix: String(prefix))?.stringValue == production else {
                    throw MeshImportError("Unsupported required 3MF extension '\(prefix)' in \(path).")
                }
            }
            guard let unit = MeshUnit(rawValue: root.value("unit") ?? "millimeter") else {
                throw MeshImportError("Unknown 3MF length unit in \(path).")
            }
            self.unit = unit
            self.element = root
            var objects: [Int: XMLElement] = [:]
            for object in children("object", of: try child("resources", of: root)) {
                let id = try object.integer("id")
                guard id > 0, objects.updateValue(object, forKey: id) == nil else {
                    throw MeshImportError("3MF object IDs must be positive and unique within \(path).")
                }
                if !isStart {
                    for group in children("components", of: object) {
                        for component in children("component", of: group)
                            where component.attribute(forLocalName: "path", uri: production) != nil {
                            throw MeshImportError("Invalid cross-part reference in child model \(path).")
                        }
                    }
                }
            }
            self.objects = objects
        }
    }

    private struct Expansion {
        let url: URL
        let root: ModelPart
        // Child components can only refer within the same child part. Keep a
        // bounded cache of parsed XML for repeated build items and components.
        let partCache = NSCache<NSString, ModelPart>()
        var assembly: ThreeMFAssembly
        var relatedParts: Set<String>?
        var mesh = EditableMesh()
        var instances = 0

        mutating func part(at path: String) throws -> ModelPart {
            if path == assembly.startPart { return root }
            if let cached = partCache.object(forKey: path as NSString) { return cached }
            if relatedParts == nil {
                var directory = assembly.startPart.components(separatedBy: "/")
                let file = directory.removeLast()
                let rels = (directory + ["_rels", file + ".rels"]).joined(separator: "/")
                relatedParts = try Set(modelTargets(rels, in: url, relativeTo: directory))
            }
            guard relatedParts?.contains(path) == true else {
                throw MeshImportError("Missing 3MF model relationship from \(assembly.startPart) to \(path).")
            }
            let loaded = try ModelPart(path: path, url: url, isStart: false)
            partCache.setObject(loaded, forKey: path as NSString, cost: loaded.byteCount)
            return loaded
        }

        mutating func append(_ ref: ThreeMFAssembly.Reference, parent: simd_double4x4, parentUnit: MeshUnit,
                             build: Int, components: [Int], ancestors: Set<ThreeMFAssembly.ObjectID>) throws {
            let key = ref.object
            let source = try part(at: key.part)
            guard let object = source.objects[key.id] else {
                throw MeshImportError("Missing 3MF object \(key.id) in \(key.part).")
            }
            guard !ancestors.contains(key) else { throw MeshImportError("Cyclic reference to object \(key.id) in \(key.part).") }
            instances += 1
            guard ancestors.count < 128, instances <= 100_000 else {
                throw MeshImportError("The 3MF assembly exceeds the nesting or instance limit.")
            }
            let world = parent * ref.transform.matrix(from: source.unit, to: parentUnit)
            if assembly.objects[key] == nil {
                let groups = children("components", of: object)
                var references: [ThreeMFAssembly.Reference] = []
                if !groups.isEmpty {
                    guard groups.count == 1, children("mesh", of: object).isEmpty else {
                        throw MeshImportError("Invalid components for 3MF object \(key.id) in \(key.part).")
                    }
                    references = try children("component", of: groups[0]).map {
                        try reference($0, in: key.part, isStart: key.part == assembly.startPart)
                    }
                    guard !references.isEmpty else { throw MeshImportError("Empty 3MF components in \(key.part).") }
                }
                assembly.objects[key] = .init(name: object.value("name"), unit: source.unit, components: references)
            }
            let references = assembly.objects[key]!.components
            if references.isEmpty {
                let firstVertex = mesh.vertices.count
                let firstFace = mesh.faces.count
                try appendMesh(child("mesh", of: object), transform: world)
                assembly.occurrences.append(.init(object: key, buildIndex: build, componentIndices: components,
                                                   importedVertices: firstVertex..<mesh.vertices.count,
                                                   importedFaceIDs: firstFace..<mesh.faces.count))
            } else {
                for (index, child) in references.enumerated() {
                    try append(child, parent: world, parentUnit: source.unit, build: build,
                               components: components + [index], ancestors: ancestors.union([key]))
                }
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
    private static func xmlPart(_ path: String, from url: URL, limit: Int) throws -> (XMLElement, Int) {
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
            return (root, data.count)
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
