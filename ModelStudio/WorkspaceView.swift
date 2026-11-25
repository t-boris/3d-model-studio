import SwiftUI
import UniformTypeIdentifiers

private struct OpenMeshKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct SaveModelKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
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
        }
    }
}

struct WorkspaceView: View {
    @StateObject private var workspace = Workspace()
    @State private var showingOpen = false
    @State private var modelingSheet: ModelingSheet?
    @State private var showingSave = false
    @State private var savingFile: EditableModelFile?

    private var canOpen: Bool {
        modelingSheet == nil && !showingOpen && !showingSave && !workspace.isReading && workspace.pendingUnits == nil
    }

    private func save() {
        guard let model = workspace.activeModel else { return }
        savingFile = EditableModelFile(model: model)
        showingSave = true
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
                            Spacer()
                            Text("Drag to rotate · Scroll to zoom")
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
        .focusedSceneValue(\.openMesh, canOpen ? { showingOpen = true } : nil)
        .focusedSceneValue(\.saveModel, canOpen && workspace.activeModel != nil ? save : nil)
        .toolbar {
            ToolbarItem {
                if workspace.isReading { ProgressView().controlSize(.small).accessibilityLabel("Reading mesh") }
            }
            ToolbarItem {
                Button { showingOpen = true } label: { Label("Open…", systemImage: "folder") }
                    .disabled(!canOpen)
            }
            ToolbarItem {
                Button(action: save) { Label("Save Editable Model…", systemImage: "square.and.arrow.down") }
                    .disabled(!canOpen || workspace.activeModel == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
            }
        }
        .fileImporter(isPresented: $showingOpen, allowedContentTypes: [.studioModel] + ["stl", "obj", "3mf"].compactMap {
            UTType(filenameExtension: $0)
        }) { result in
            switch result {
            case .success(let url): Task { await workspace.open(url) }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { workspace.modelError = error.localizedDescription }
            }
        }
        .fileExporter(isPresented: $showingSave, document: savingFile, contentType: .studioModel,
                      defaultFilename: savingFile.map { ($0.model.name as NSString).deletingPathExtension }) { result in
            savingFile = nil
            if case .failure(let error) = result, (error as NSError).code != NSUserCancelledError {
                workspace.modelError = error.localizedDescription
            }
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
