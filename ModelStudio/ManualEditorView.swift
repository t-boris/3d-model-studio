import SwiftUI

private enum ManualTool: String, CaseIterable {
    case point = "Move Point"
    case surface = "Reshape Surface"
    case extrusion = "Extrude"
}

struct ManualEditorView: View {
    @ObservedObject var workspace: Workspace
    let model: WorkspaceModel
    let editingEnabled: Bool
    let request: (ModelingScope) -> Void
    @State private var tool = ManualTool.point
    @State private var selectedPoint: Int?
    @State private var selectedFaces: Set<Int> = []
    @State private var axis = ModelDimension.height
    @State private var unit: MeshUnit
    @State private var distance = ""

    init(workspace: Workspace, model: WorkspaceModel, editingEnabled: Bool, request: @escaping (ModelingScope) -> Void) {
        self.request = request
        self.workspace = workspace
        self.model = model
        self.editingEnabled = editingEnabled
        _unit = State(initialValue: model.unit)
    }

    private var edit: ManualMeshEdit? {
        switch tool {
        case .point: selectedPoint.map { .movePoint($0, axis: axis) }
        case .surface: selectedFaces.isEmpty ? nil : .reshape(selectedFaces, axis: axis)
        case .extrusion: selectedFaces.isEmpty ? nil : .extrude(selectedFaces)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ModelViewport(mesh: model.mesh, selectedFaces: tool == .point ? [] : selectedFaces,
                          selectedPoint: tool == .point ? selectedPoint : nil) { face, point in
                guard editingEnabled else { return }
                if tool == .point {
                    selectedPoint = point
                } else if !selectedFaces.insert(face).inserted {
                    selectedFaces.remove(face)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Picker("Edit tool", selection: $tool) {
                    ForEach(ManualTool.allCases, id: \.self) { tool in Text(tool.rawValue).tag(tool) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Menu("Ask Agent") {
                        Button("Revise Entire Model…") { request(.revision(model)) }
                        Button("Edit Selected Faces…") { request(.selection(model, selectedFaces)) }
                            .disabled(tool == .point || selectedFaces.isEmpty)
                        Button("Continue Creating This Model…") { request(.creation(draft: model)) }
                    }.fixedSize()
                    selectionLabel
                    Spacer()
                    if edit != nil {
                        Button("Clear Selection") {
                            if tool == .point { selectedPoint = nil } else { selectedFaces.removeAll() }
                        }
                    }
                }
                HStack {
                    if tool != .extrusion {
                        Picker("Axis", selection: $axis) {
                            Text("X").tag(ModelDimension.width)
                            Text("Y").tag(ModelDimension.depth)
                            Text("Z").tag(ModelDimension.height)
                        }.fixedSize()
                    } else {
                        Text("Along face normal")
                    }
                    TextField(tool == .extrusion ? "Distance" : "Signed offset", text: $distance)
                        .frame(width: 100)
                        .onSubmit(apply)
                    Picker("Distance unit", selection: $unit) {
                        ForEach(MeshUnit.allCases, id: \.self) { unit in Text(unit.symbol).tag(unit) }
                    }.labelsHidden().fixedSize()
                    Button("Apply", action: apply).disabled(edit == nil || distance.isEmpty)
                }
            }
            .disabled(!editingEnabled)
            .padding(10)
            .background(.bar)
        }
        .onChange(of: model.mesh.faces) { _, faces in
            selectedFaces.formIntersection(faces.map(\.id))
        }
    }

    @ViewBuilder private var selectionLabel: some View {
        if tool == .point, let index = selectedPoint, model.mesh.vertices.indices.contains(index) {
            let p = model.mesh.vertices[index]
            Text("Point \(index) · (\(p.x.formatted()), \(p.y.formatted()), \(p.z.formatted())) \(model.unit.symbol)")
        } else if tool == .point {
            Text("Click near a corner to select its point.")
        } else if selectedFaces.isEmpty {
            Text(tool == .extrusion ? "Click triangles to select a flat patch." : "Click triangles to select the surface to move.")
        } else {
            Text("\(selectedFaces.count) selected · Click a triangle to toggle it.")
        }
    }

    private func apply() {
        guard editingEnabled, let edit else { return }
        let number = distance.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
        guard let value = Double(number) else {
            workspace.modelError = "Enter a numeric distance in \(unit.symbol)."
            return
        }
        do {
            try workspace.applyManualEdit(edit, basedOn: model, distance: value, unit: unit)
            distance = ""
        } catch {
            workspace.modelError = error.localizedDescription
        }
    }
}
