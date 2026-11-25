import Combine
import Foundation

@MainActor
final class Workspace: ObservableObject {
    @Published private(set) var activeModel: WorkspaceModel? {
        didSet {
            if oldValue?.id != activeModel?.id {
                printValidation = .unchecked
                return
            }
            switch printValidation {
            case .current, .checking:
                if oldValue?.mesh != activeModel?.mesh { printValidation = .stale }
            case .unchecked, .stale:
                break
            }
        }
    }
    @Published private(set) var printValidation: PrintValidationState = .unchecked
    @Published var pendingUnits: MeshImport?
    @Published var modelError: String?
    @Published private(set) var fileOperationInProgress = false
    private let dialogs: any WorkspaceFileDialogs
    private var baseline: WorkspaceModel?

    convenience init() { self.init(dialogs: MacWorkspaceFileDialogs()) }

    init(dialogs: any WorkspaceFileDialogs) {
        self.dialogs = dialogs
    }

    var canStartFileOperation: Bool { !fileOperationInProgress && pendingUnits == nil }

    var hasUnsavedChanges: Bool {
        guard let model = activeModel else { return false }
        guard let baseline else { return true } // Newly created geometry.
        return model.mesh != baseline.mesh || model.unit != baseline.unit ||
            model.pins.count != baseline.pins.count || !model.pins.allSatisfy(baseline.pins.contains)
    }

    func validatePrintGeometry() async {
        guard let mesh = activeModel?.mesh else { return }
        if case .checking = printValidation { return }
        let token = UUID()
        printValidation = .checking(token)
        let report = await Task.detached(priority: .userInitiated) { PrintGeometryReport(mesh: mesh) }.value
        // A later edit, replacement or recheck can supersede this result.
        guard case .checking(let current) = printValidation, current == token else { return }
        printValidation = .current(report)
    }

    enum ExportResult { case written, invalidGeometry, cancelled, failed }

    func exportCore3MF() async -> ExportResult {
        guard canStartFileOperation, let model = activeModel else { return .cancelled }
        fileOperationInProgress = true
        defer { fileOperationInProgress = false }
        let previous = printValidation
        printValidation = .checking(UUID())
        do {
            let export = try await Task.detached(priority: .userInitiated) { try CoreThreeMFExport(model: model) }.value
            printValidation = .current(export.report)
            guard !Task.isCancelled, let url = try dialogs.exportDestination(modelName: model.name) else { return .cancelled }
            try await Task.detached(priority: .userInitiated) { try export.write(to: url) }.value
            return .written
        } catch let error as CoreThreeMFExport.InvalidGeometry {
            printValidation = .current(error.report)
            return .invalidGeometry
        } catch {
            if case .checking = printValidation {
                if case .checking = previous { printValidation = .unchecked }
                else { printValidation = previous }
            }
            modelError = error.localizedDescription
            return .failed
        }
    }

    func save() async -> Bool {
        guard canStartFileOperation else { return false }
        fileOperationInProgress = true
        defer { fileOperationInProgress = false }
        return await saveActiveModel()
    }

    private func saveActiveModel() async -> Bool {
        guard let model = activeModel else { return false }
        do {
            guard let url = try dialogs.saveDestination(modelName: model.name) else { return false }
            try await Task.detached(priority: .userInitiated) {
                try EditableModelFile(model: model).write(to: url)
            }.value
            baseline = model
            return true
        } catch {
            modelError = error.localizedDescription
            return false
        }
    }

    private func canLeaveModel(quitting: Bool) async -> Bool {
        guard let model = activeModel, hasUnsavedChanges else { return true }
        switch dialogs.confirmChanges(modelName: model.name, quitting: quitting) {
        case .save: return await saveActiveModel()
        case .discard: return true
        case .cancel: return false
        }
    }

    func shouldQuit() async -> Bool {
        guard canStartFileOperation else { return false }
        fileOperationInProgress = true
        defer { fileOperationInProgress = false }
        return await canLeaveModel(quitting: true)
    }

    func open(_ source: URL? = nil) async {
        guard canStartFileOperation else { return }
        fileOperationInProgress = true
        defer { fileOperationInProgress = false }
        guard await canLeaveModel(quitting: false), !Task.isCancelled else { return }
        var fileName: String?
        do {
            guard let url = try source ?? dialogs.openSource() else { return }
            fileName = url.lastPathComponent
            if url.pathExtension.lowercased() == EditableModelFile.fileExtension {
                let model = try await Task.detached(priority: .userInitiated) {
                    try EditableModelFile.read(url)
                }.value
                guard !Task.isCancelled else { return }
                install(model)
                return
            }
            let loaded = try await Task.detached(priority: .userInitiated) { try MeshImport.read(url) }.value
            guard !Task.isCancelled else { return }
            if let unit = loaded.unit {
                install(try loaded.model(in: unit))
            } else {
                pendingUnits = loaded
            }
        } catch {
            modelError = (fileName.map { $0 + "\n" } ?? "") + error.localizedDescription
        }
    }

    private func install(_ model: WorkspaceModel) {
        baseline = model
        activeModel = model
    }

    func acceptUnit(_ unit: MeshUnit) {
        guard let pendingUnits else { return }
        do { install(try pendingUnits.model(in: unit)) }
        catch { modelError = error.localizedDescription }
        self.pendingUnits = nil
    }

    func newBlock() {
        guard canStartFileOperation, activeModel == nil else { return }
        do { activeModel = try WorkspaceModel.newBlock() }
        catch { modelError = error.localizedDescription }
    }

    // A delayed proposal belongs to the model and geometry it was prepared
    // against. Check the current pins even if only pin metadata has changed.
    func commit(_ proposal: EditableMesh, basedOn original: WorkspaceModel,
                requested: [DimensionTarget] = []) throws {
        try editModel(basedOn: original) { current in
            try current.commit(proposal, requested: requested)
        }
    }

    private func editModel(basedOn original: WorkspaceModel? = nil,
                           _ edit: (inout WorkspaceModel) throws -> Void) throws {
        let staleModel = MeshImportError("The model changed. Prepare the edit again using the current geometry.")
        guard canStartFileOperation, var current = activeModel else { throw staleModel }
        if let original, original.id != current.id || original.mesh != current.mesh {
            throw staleModel
        }
        try edit(&current)
        activeModel = current
    }

    func commitCreation(_ proposal: EditableMesh, unit: MeshUnit, requested: [DimensionTarget]) throws {
        guard canStartFileOperation, activeModel == nil else {
            throw MeshImportError("The workspace changed. Prepare the creation again in an empty workspace.")
        }
        activeModel = try WorkspaceModel(name: "Untitled Model", unit: unit, mesh: proposal, requested: requested)
    }

    func applyManualEdit(_ edit: ManualMeshEdit, basedOn model: WorkspaceModel,
                         distance: Double, unit: MeshUnit) throws {
        try editModel(basedOn: model) { current in
            let proposal = try edit.proposal(for: current, distance: distance, unit: unit)
            try current.commit(proposal)
        }
    }

    func pinCurrent(_ dimension: ModelDimension) {
        guard canStartFileOperation else { return }
        do { try activeModel?.pinCurrent(dimension) }
        catch { modelError = error.localizedDescription }
    }

    func unpin(_ dimension: ModelDimension) {
        guard canStartFileOperation else { return }
        activeModel?.unpin(dimension)
    }

    func resize(to target: DimensionTarget, changingPin: Bool) -> Bool {
        guard canStartFileOperation, activeModel != nil else { return false }
        do {
            try editModel { current in
                try current.resize(to: target, changingPin: changingPin)
            }
            return true
        } catch {
            modelError = error.localizedDescription
            return false
        }
    }
}
