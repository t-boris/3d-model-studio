import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let studioModel = UTType(exportedAs: "com.github.t-boris.3d-model-studio.model", conformingTo: .data)
}

struct EditableModelFile: FileDocument {
    static let readableContentTypes = [UTType.studioModel]
    static let fileExtension = "studio3d"

    private struct Archive: Codable {
        let version: Int
        let name: String
        let unit: MeshUnit
        let mesh: EditableMesh
        let pins: [DimensionTarget]
    }

    let model: WorkspaceModel

    init(model: WorkspaceModel) { self.model = model }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw MeshImportError("Choose a Model Studio file.")
        }
        self = try Self(data: data)
    }

    init(data: Data) throws {
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.version == 1 else {
            throw MeshImportError("Unsupported Model Studio file version \(archive.version).")
        }
        model = try WorkspaceModel(name: archive.name, unit: archive.unit, mesh: archive.mesh, pins: archive.pins)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(regularFileWithContents: encoded())
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(Archive(version: 1, name: model.name, unit: model.unit,
                                         mesh: model.mesh, pins: model.pins))
    }

    // The version-1 mesh includes its optional assembly inline. Older files
    // without that field decode as standalone indexed meshes.
    func write(to url: URL) throws {
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        try encoded().write(to: url, options: .atomic)
    }

    static func read(_ url: URL) throws -> WorkspaceModel {
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        return try Self(data: Data(contentsOf: url)).model
    }
}
