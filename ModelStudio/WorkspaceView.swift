import SwiftUI

private struct OpenMeshKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct SaveModelKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ExportModelKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var exportModel: (() -> Void)? {
        get { self[ExportModelKey.self] }
        set { self[ExportModelKey.self] = newValue }
    }

    var saveModel: (() -> Void)? {
        get { self[SaveModelKey.self] }
        set { self[SaveModelKey.self] = newValue }
    }

    var openMesh: (() -> Void)? {
        get { self[OpenMeshKey.self] }
        set { self[OpenMeshKey.self] = newValue }
    }
}

struct WorkspaceCommands: Commands {
    @FocusedValue(\.openMesh) private var openMesh
    @FocusedValue(\.saveModel) private var saveModel

    @FocusedValue(\.exportModel) private var exportModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open…") { openMesh?() }
                .keyboardShortcut("o")
                .disabled(openMesh == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Editable Model…") { saveModel?() }
                .keyboardShortcut("s")
                .disabled(saveModel == nil)
            Button("Export Core 3MF…") { exportModel?() }
                .disabled(exportModel == nil)
        }
    }
}

struct WorkspaceView: View {
    @ObservedObject var workspace: Workspace
    @State private var modelingSheet: ModelingSheet?
    @State private var showingPrintChecks = false
    private var canOpen: Bool {
        modelingSheet == nil && !showingPrintChecks && workspace.canStartFileOperation
    }

    private func open() { Task { await workspace.open() } }
    private func save() { Task { await workspace.save() } }

    private func export() {
        Task {
            if await workspace.exportCore3MF() == .invalidGeometry { showingPrintChecks = true }
        }
    }

    var body: some View {
        Group {
            if let model = workspace.activeModel {
                ManualEditorView(workspace: workspace, model: model, editingEnabled: canOpen) { scope in
                    modelingSheet = ModelingSheet(scope: scope)
                }
                    .id(model.id)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        DimensionControls(workspace: workspace, model: model)
                            .id(model.id)
                            .disabled(!canOpen)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        HStack {
                            Text("\(model.mesh.vertices.count) vertices · \(model.mesh.faces.count) faces · \(model.unit.symbol)")
                            Button("Print Checks · \(workspace.printValidation.label)") { showingPrintChecks = true }
                                .disabled(!canOpen)
                                .accessibilityIdentifier("openPrintChecks")
                            Spacer()
                            Text("Scroll to zoom")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(.bar)
                    }
            } else {
                ContentUnavailableView {
                    Label("No Geometry", systemImage: "cube.transparent")
                } description: {
                    Text("Create a block or open an editable model, STL, OBJ, or 3MF.")
                } actions: {
                    Button("Create from Description…") { modelingSheet = ModelingSheet(scope: .creation(draft: nil)) }
                        .disabled(!canOpen)
                    Button("New Block", action: workspace.newBlock).disabled(!canOpen)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("modelViewport")
        .navigationTitle(workspace.activeModel?.name ?? "Untitled")
        .focusedSceneValue(\.openMesh, canOpen ? open : nil)
        .focusedSceneValue(\.saveModel, canOpen && workspace.activeModel != nil ? save : nil)
        .focusedSceneValue(\.exportModel, canOpen && workspace.activeModel != nil ? export : nil)
        .toolbar {
            ToolbarItem {
                if workspace.fileOperationInProgress { ProgressView().controlSize(.small).accessibilityLabel("Model file operation") }
            }
            ToolbarItem {
                Button(action: open) { Label("Open…", systemImage: "folder") }
                    .disabled(!canOpen)
            }
            ToolbarItem {
                Button(action: save) { Label("Save Editable Model…", systemImage: "square.and.arrow.down") }
                    .disabled(!canOpen || workspace.activeModel == nil)
            }
            ToolbarItem {
                Button(action: export) { Label("Export Core 3MF…", systemImage: "square.and.arrow.up") }
                    .disabled(!canOpen || workspace.activeModel == nil)
                    .accessibilityIdentifier("exportCore3MF")
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
            }
        }
        .sheet(isPresented: $showingPrintChecks) {
            PrintChecksView(workspace: workspace)
        }
        .sheet(item: $modelingSheet) { sheet in
            ModelingRequestView(scope: sheet.scope, workspace: workspace)
        }
        .sheet(item: $workspace.pendingUnits) { loaded in
            UnitChoiceView(fileName: loaded.name, accept: workspace.acceptUnit) {
                workspace.pendingUnits = nil
            }
        }
        .alert("Model operation couldn’t be completed", isPresented: Binding(
            get: { workspace.modelError != nil },
            set: { if !$0 { workspace.modelError = nil } }
        )) {
            Button("OK") { workspace.modelError = nil }
        } message: {
            Text(workspace.modelError ?? "")
        }
    }
}

private struct UnitChoiceView: View {
    let fileName: String
    let accept: (MeshUnit) -> Void
    let cancel: () -> Void
    @State private var unit: MeshUnit?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose the source unit").font(.headline)
            Text("\(fileName) has no standard length unit. Which unit was used for its coordinates?")
            Picker("Unit", selection: $unit) {
                Text("Choose a unit…").tag(nil as MeshUnit?)
                ForEach(MeshUnit.allCases, id: \.self) { option in
                    Text("\(option.rawValue.capitalized) (\(option.symbol))").tag(Optional(option))
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Open") { if let unit { accept(unit) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(unit == nil)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
