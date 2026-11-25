import SwiftUI
import UniformTypeIdentifiers

private struct OpenMeshKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openMesh: (() -> Void)? {
        get { self[OpenMeshKey.self] }
        set { self[OpenMeshKey.self] = newValue }
    }
}

struct WorkspaceCommands: Commands {
    @FocusedValue(\.openMesh) private var openMesh

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open…") { openMesh?() }
                .keyboardShortcut("o")
                .disabled(openMesh == nil)
        }
    }
}

@MainActor
final class Workspace: ObservableObject {
    @Published var activeModel: WorkspaceModel?
    @Published var pendingUnits: MeshImport?
    @Published var importError: String?
    @Published private(set) var isReading = false

    func open(_ url: URL) async {
        guard !isReading, pendingUnits == nil else { return }
        isReading = true
        defer { isReading = false }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { try MeshImport.read(url) }.value
            if let unit = loaded.unit {
                activeModel = loaded.model(in: unit)
            } else {
                pendingUnits = loaded
            }
        } catch {
            importError = "\(url.lastPathComponent)\n\(error.localizedDescription)"
        }
    }

    func acceptUnit(_ unit: MeshUnit) {
        guard let pendingUnits else { return }
        activeModel = pendingUnits.model(in: unit)
        self.pendingUnits = nil
    }
}

struct WorkspaceView: View {
    @StateObject private var workspace = Workspace()
    @State private var showingOpen = false

    private var canOpen: Bool {
        !showingOpen && !workspace.isReading && workspace.pendingUnits == nil
    }

    var body: some View {
        Group {
            if let model = workspace.activeModel {
                ModelViewport(mesh: model.mesh)
                    .id(model.id)
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
                ContentUnavailableView("No Geometry", systemImage: "cube.transparent",
                                       description: Text("Open an STL, OBJ, or 3MF model."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("modelViewport")
        .navigationTitle(workspace.activeModel?.name ?? "Untitled")
        .focusedSceneValue(\.openMesh, canOpen ? { showingOpen = true } : nil)
        .toolbar {
            ToolbarItem {
                if workspace.isReading { ProgressView().controlSize(.small).accessibilityLabel("Reading mesh") }
            }
            ToolbarItem {
                Button { showingOpen = true } label: { Label("Open…", systemImage: "folder") }
                    .disabled(!canOpen)
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
            }
        }
        .fileImporter(isPresented: $showingOpen, allowedContentTypes: ["stl", "obj", "3mf"].compactMap {
            UTType(filenameExtension: $0)
        }) { result in
            switch result {
            case .success(let url): Task { await workspace.open(url) }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { workspace.importError = error.localizedDescription }
            }
        }
        .sheet(item: $workspace.pendingUnits) { loaded in
            UnitChoiceView(fileName: loaded.name, accept: workspace.acceptUnit) {
                workspace.pendingUnits = nil
            }
        }
        .alert("Couldn’t open model", isPresented: Binding(
            get: { workspace.importError != nil },
            set: { if !$0 { workspace.importError = nil } }
        )) {
            Button("OK") { workspace.importError = nil }
        } message: {
            Text(workspace.importError ?? "")
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
