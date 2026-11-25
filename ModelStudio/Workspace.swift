import Combine
import Foundation

@MainActor
final class Workspace: ObservableObject {
    @Published private(set) var activeModel: WorkspaceModel?
    @Published var pendingUnits: MeshImport?
    @Published var modelError: String?
    @Published private(set) var isReading = false

    func open(_ url: URL) async {
        guard !isReading, pendingUnits == nil else { return }
        isReading = true
        defer { isReading = false }
        do {
            if url.pathExtension.lowercased() == EditableModelFile.fileExtension {
                activeModel = try await Task.detached(priority: .userInitiated) {
                    try EditableModelFile.read(url)
                }.value
                return
            }
            let loaded = try await Task.detached(priority: .userInitiated) { try MeshImport.read(url) }.value
            if let unit = loaded.unit {
                activeModel = try loaded.model(in: unit)
            } else {
                pendingUnits = loaded
            }
        } catch {
            modelError = "\(url.lastPathComponent)\n\(error.localizedDescription)"
        }
    }

    func acceptUnit(_ unit: MeshUnit) {
        guard let pendingUnits else { return }
        do { activeModel = try pendingUnits.model(in: unit) }
        catch { modelError = error.localizedDescription }
        self.pendingUnits = nil
    }

    func newBlock() {
        guard activeModel == nil else { return }
        do { activeModel = try WorkspaceModel.newBlock() }
        catch { modelError = error.localizedDescription }
    }

    // A delayed proposal belongs to the model and geometry it was prepared
    // against. Check the current pins even if only pin metadata has changed.
    func commit(_ proposal: EditableMesh, basedOn original: WorkspaceModel,
                requested: [DimensionTarget] = []) throws {
        guard let current = activeModel, original.id == current.id, original.mesh == current.mesh else {
            throw MeshImportError("The model changed. Prepare the edit again using the current geometry.")
        }
        try activeModel?.commit(proposal, requested: requested)
    }

    func commitCreation(_ proposal: EditableMesh, unit: MeshUnit, requested: [DimensionTarget]) throws {
        guard activeModel == nil else {
            throw MeshImportError("The workspace changed. Prepare the creation again in an empty workspace.")
        }
        activeModel = try WorkspaceModel(name: "Untitled Model", unit: unit, mesh: proposal, requested: requested)
    }

    func applyManualEdit(_ edit: ManualMeshEdit, basedOn model: WorkspaceModel,
                         distance: Double, unit: MeshUnit) throws {
        let proposal = try edit.proposal(for: model, distance: distance, unit: unit)
        try commit(proposal, basedOn: model)
    }

    func pinCurrent(_ dimension: ModelDimension) {
        do { try activeModel?.pinCurrent(dimension) }
        catch { modelError = error.localizedDescription }
    }

    func unpin(_ dimension: ModelDimension) {
        activeModel?.unpin(dimension)
    }

    func resize(to target: DimensionTarget, changingPin: Bool) -> Bool {
        guard activeModel != nil else { return false }
        do {
            try activeModel?.resize(to: target, changingPin: changingPin)
            return true
        } catch {
            modelError = error.localizedDescription
            return false
        }
    }
}
