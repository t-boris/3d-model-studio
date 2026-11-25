import Foundation
import simd

/// Only a successfully checked archive can reach the destination writer.
struct CoreThreeMFExport {
    let report: PrintGeometryReport
    private let package: Data

    struct InvalidGeometry: Error {
        let report: PrintGeometryReport
    }

    init(model: WorkspaceModel) throws {
        let sourceReport = PrintGeometryReport(mesh: model.mesh)
        guard sourceReport.passed else { throw InvalidGeometry(report: sourceReport) }

        var writer = ModelPartWriter(model: model)
        let xml = try writer.render()
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: directory) }
        let archive = try Self.archive(xml, in: directory)

        // Validate the assembled surface read from the exact bytes to be copied.
        // The maps take any issue back to the editable faces and shared points.
        let (written, unit) = try ThreeMFReader.read(archive)
        guard unit == .millimeter, written.faces.count == model.mesh.faces.count,
              written.vertices.count == writer.vertexIDs.count,
              written.faces.count == writer.faceIDs.count else {
            throw MeshImportError("The Core 3MF package did not preserve the complete surface.")
        }
        let checked = PrintGeometryReport(mesh: written)
        guard checked.passed else {
            let issues = checked.issues.map { issue in
                PrintGeometryReport.Issue(problem: issue.problem, faces: issue.faces.map { writer.faceIDs[$0] },
                    edge: issue.edge.map { SIMD2(writer.vertexIDs[$0.x], writer.vertexIDs[$0.y]) },
                    markerVertex: writer.vertexIDs[issue.markerVertex])
            }
            throw InvalidGeometry(report: PrintGeometryReport(issues: issues))
        }
        for (index, point) in written.vertices.enumerated() {
            let original = model.mesh.vertices[writer.vertexIDs[index]] * model.unit.millimetersPerUnit
            for axis in 0..<3 where !DimensionTarget.matches(measuredMM: point[axis], targetMM: original[axis]) {
                throw MeshImportError("Core 3MF placement exceeds the millimeter tolerance at vertex \(writer.vertexIDs[index]).")
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: model.mesh.faces.map { ($0.id, $0.vertices) })
        for (index, face) in written.faces.enumerated() {
            let v = face.vertices
            let corners = SIMD3(writer.vertexIDs[v.x], writer.vertexIDs[v.y], writer.vertexIDs[v.z])
            guard corners == byID[writer.faceIDs[index]] else {
                throw MeshImportError("The Core 3MF package changed the corners of face \(writer.faceIDs[index]).")
            }
        }
        let (low, high) = written.surfaceBounds
        for dimension in ModelDimension.allCases {
            let target = DimensionTarget(dimension: dimension, value: model.extents[dimension.axis], unit: model.unit)
            try target.check(extents: high - low, modelUnit: .millimeter, pinned: false)
        }
        self.report = checked
        self.package = try Data(contentsOf: archive, options: .mappedIfSafe)
    }

    func write(to destination: URL) throws {
        let scope = destination.startAccessingSecurityScopedResource()
        defer { if scope { destination.stopAccessingSecurityScopedResource() } }
        try package.write(to: destination, options: .atomic)
    }

    private static func archive(_ model: String, in directory: URL) throws -> URL {
        let types = """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
        </Types>
        """
        let relationships = """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="model" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" Target="/3D/3dmodel.model"/>
        </Relationships>
        """
        let parts = [("[Content_Types].xml", types), ("_rels/.rels", relationships), ("3D/3dmodel.model", model)]
        for (name, contents) in parts {
            let url = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: false, encoding: .utf8)
        }
        let zip = Process()
        zip.currentDirectoryURL = directory
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-X", "output.zip"] + parts.map(\.0)
        try zip.run()
        zip.waitUntilExit()
        guard zip.terminationStatus == 0 else { throw MeshImportError("Couldn’t package the Core 3MF model.") }
        return directory.appendingPathComponent("output.zip")
    }
}

private struct ModelPartWriter {
    let model: WorkspaceModel
    private var resources = ""
    private var resourceCount = 0
    // Reuse a source resource only when its exported mesh or child references also match.
    private var variants: [ThreeMFAssembly.ObjectID: [String: Int]] = [:]
    private var occurrenceIndex = 0
    private var faceGroups: [Int?: [Int]] = [:]
    private(set) var vertexIDs: [Int] = []
    private(set) var faceIDs: [Int] = []

    init(model: WorkspaceModel) { self.model = model }

    mutating func render() throws -> String {
        var build = ""
        if let assembly = model.mesh.assembly {
            faceGroups = assembly.groupByOccurrence(model.mesh.faces.map(\.id))
            guard faceGroups[nil] == nil else { throw MeshImportError("A face has no 3MF occurrence mapping.") }
            let indices = Dictionary(uniqueKeysWithValues: model.mesh.faces.enumerated().map { ($1.id, $0) })
            for (index, reference) in assembly.buildItems.enumerated() {
                build += try element("item", reference, in: assembly, parentUnit: model.unit,
                                     parent: matrix_identity_double4x4, build: index, path: [], indices: indices)
            }
            guard occurrenceIndex == assembly.occurrences.count else {
                throw MeshImportError("The saved assembly has unmatched occurrences.")
            }
        } else {
            let mesh = try surface(model.mesh.faces, world: matrix_identity_double4x4)
            let id = resource(mesh, name: model.name, source: nil)
            build = "<item objectid=\"\(id)\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <model xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" unit="millimeter" xml:lang="en-US">
        <resources>\(resources)</resources><build>\(build)</build></model>
        """
    }

    private mutating func element(_ tag: String, _ reference: ThreeMFAssembly.Reference, in assembly: ThreeMFAssembly,
                                  parentUnit: MeshUnit, parent: simd_double4x4, build: Int, path: [Int],
                                  indices: [Int: Int]) throws -> String {
        guard path.count < 128, let object = assembly.objects[reference.object] else {
            throw MeshImportError("The saved assembly has an invalid component reference.")
        }
        // All Core resources use mm. Linear bases stay dimensionless and translations
        // use the referencing part's unit, including at the build item.
        var transform = reference.transform.matrix(from: .millimeter, to: .millimeter)
        transform.columns.3 = SIMD4(reference.transform.origin * parentUnit.millimetersPerUnit, 1)
        let world = parent * transform
        let body: String
        if object.components.isEmpty {
            guard assembly.occurrences.indices.contains(occurrenceIndex) else {
                throw MeshImportError("The saved assembly is missing an occurrence.")
            }
            let occurrence = assembly.occurrences[occurrenceIndex]
            guard occurrence.buildIndex == build, occurrence.componentIndices == path,
                  occurrence.object == reference.object else {
                throw MeshImportError("The saved face mapping does not match the assembly hierarchy.")
            }
            let ids = faceGroups[occurrenceIndex] ?? []
            occurrenceIndex += 1
            // An edit can delete an entire leaf. Core mesh objects must contain triangles.
            guard !ids.isEmpty else { return "" }
            body = try surface(ids.map { model.mesh.faces[indices[$0]!] }, world: world)
        } else {
            var children = ""
            for (index, child) in object.components.enumerated() {
                children += try element("component", child, in: assembly, parentUnit: object.unit,
                                        parent: world, build: build, path: path + [index], indices: indices)
            }
            guard !children.isEmpty else { return "" }
            body = "<components>\(children)</components>"
        }
        let id = resource(body, name: object.name, source: reference.object)
        let numbers = (0..<4).flatMap { column in (0..<3).map { String(transform[column][$0]) } }
        return "<\(tag) objectid=\"\(id)\" transform=\"\(numbers.joined(separator: " "))\"/>"
    }

    private mutating func surface(_ faces: [MeshFace], world: simd_double4x4) throws -> String {
        let determinant = simd_determinant(world)
        guard determinant.isFinite, determinant != 0 else {
            throw MeshImportError("The assembly placement cannot be inverted for Core 3MF export.")
        }
        let inverse = world.inverse
        let used = Set(faces.flatMap { [$0.vertices.x, $0.vertices.y, $0.vertices.z] }).sorted()
        var local: [Int: Int] = [:]
        var xml = "<mesh><vertices>"
        for (index, vertex) in used.enumerated() {
            let mm = model.mesh.vertices[vertex] * model.unit.millimetersPerUnit
            let p = inverse * SIMD4(mm, 1)
            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else {
                throw MeshImportError("Vertex \(vertex) exceeds the Core 3MF coordinate range.")
            }
            local[vertex] = index
            xml += "<vertex x=\"\(p.x)\" y=\"\(p.y)\" z=\"\(p.z)\"/>\n"
        }
        xml += "</vertices><triangles>"
        for face in faces {
            let v = face.vertices
            let b = determinant < 0 ? v.z : v.y
            let c = determinant < 0 ? v.y : v.z
            xml += "<triangle v1=\"\(local[v.x]!)\" v2=\"\(local[b]!)\" v3=\"\(local[c]!)\"/>\n"
        }
        vertexIDs.append(contentsOf: used)
        faceIDs.append(contentsOf: faces.map(\.id))
        return xml + "</triangles></mesh>"
    }

    private mutating func resource(_ body: String, name: String?, source: ThreeMFAssembly.ObjectID?) -> Int {
        if let source, let id = variants[source]?[body] { return id }
        resourceCount += 1
        let nameAttribute = name.map { " name=\"\(Self.escaped($0))\"" } ?? ""
        resources += "<object id=\"\(resourceCount)\" type=\"model\"\(nameAttribute)>\(body)</object>\n"
        if let source { variants[source, default: [:]][body] = resourceCount }
        return resourceCount
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
