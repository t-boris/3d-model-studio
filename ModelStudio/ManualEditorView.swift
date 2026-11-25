import SwiftUI
import simd

private enum ManualTool: String, CaseIterable {
    case orbit = "Orbit"
    case point = "Move Point"
    case surface = "Reshape Surface"
    case extrusion = "Extrude"

    var icon: String {
        switch self {
        case .orbit: "rotate.3d"
        case .point: "arrow.up.and.down.and.arrow.left.and.right"
        case .surface: "square.on.square"
        case .extrusion: "cube"
        }
    }

    var editsFaces: Bool { self == .surface || self == .extrusion }
}

struct ManualEditorView: View {
    @ObservedObject var workspace: Workspace
    let model: WorkspaceModel
    let editingEnabled: Bool
    let request: (ModelingScope) -> Void
    @State private var tool = ManualTool.orbit
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
        case .orbit: nil
        case .point: selectedPoint.map { .movePoint($0, axis: axis) }
        case .surface: selectedFaces.isEmpty ? nil : .reshape(selectedFaces, axis: axis)
        case .extrusion: selectedFaces.isEmpty ? nil : .extrude(selectedFaces)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                editTools
                Divider()
                ModelViewport(mesh: model.mesh, selectedFaces: tool.editsFaces ? selectedFaces : [],
                              selectedPoint: tool == .point ? selectedPoint : nil,
                              showsOrientation: true, beginEdit: tool != .orbit && editingEnabled ? beginDrag : nil,
                              pick: pick)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Menu("Ask Agent") {
                        Button("Revise Entire Model…") { request(.revision(model)) }
                        Button("Edit Selected Faces…") { request(.selection(model, selectedFaces)) }
                            .disabled(!tool.editsFaces || selectedFaces.isEmpty)
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
                if tool != .orbit {
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
            }
            .disabled(!editingEnabled)
            .padding(10)
            .background(.bar)
        }
        .onChange(of: model.mesh.faces) { _, faces in
            selectedFaces.formIntersection(faces.map(\.id))
        }
    }

    private var editTools: some View {
        VStack(spacing: 6) {
            ForEach(ManualTool.allCases, id: \.self) { option in
                Button { tool = option } label: {
                    Image(systemName: option.icon)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 36, height: 34)
                        .background(tool == option ? Color.accentColor.opacity(0.18) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(option.rawValue)
                .accessibilityLabel(option.rawValue)
                .accessibilityAddTraits(tool == option ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.bar)
        .disabled(!editingEnabled)
    }

    @ViewBuilder private var selectionLabel: some View {
        if tool == .point, let index = selectedPoint, model.mesh.vertices.indices.contains(index) {
            let p = model.mesh.vertices[index]
            Text("Point \(index) · (\(p.x.formatted()), \(p.y.formatted()), \(p.z.formatted())) \(model.unit.symbol)")
        } else if tool == .point {
            Text("Drag a corner to move its point.")
        } else if tool == .orbit {
            Text("Drag to orbit or click a face of the view cube.")
        } else if selectedFaces.isEmpty {
            Text(tool == .extrusion ? "Select a flat patch, then drag it outward." : "Select triangles, then drag to reshape the surface.")
        } else {
            Text("\(selectedFaces.count) selected · Click a triangle to toggle it.")
        }
    }

    private func pick(_ face: Int, _ point: Int) {
        guard editingEnabled else { return }
        if tool == .point {
            selectedPoint = point
        } else if tool.editsFaces, !selectedFaces.insert(face).inserted {
            selectedFaces.remove(face)
        }
    }

    private func beginDrag(_ face: Int, _ point: Int) -> ViewportEdit? {
        guard editingEnabled, tool != .orbit else { return nil }
        let selection = selectedFaces.contains(face) ? selectedFaces : [face]
        let normal = tool == .extrusion ? (try? ManualMeshEdit.extrusionNormal(for: model, selection: selection)) : nil
        return ViewportEdit(point: tool == .point ? point : nil, normal: normal) { delta in
            let distance = simd_length(delta)
            let edit: ManualMeshEdit
            switch tool {
            case .orbit: return
            case .point:
                selectedPoint = point
                edit = .movePoint(point, direction: delta / distance)
            case .surface:
                selectedFaces = selection
                edit = .reshape(selection, direction: delta / distance)
            case .extrusion:
                selectedFaces = selection
                // An invalid patch still reaches the shared transaction so it can show the reason.
                edit = .extrude(selection)
            }
            apply(edit, distance: distance, unit: model.unit)
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
        apply(edit, distance: value, unit: unit)
    }

    private func apply(_ edit: ManualMeshEdit, distance value: Double, unit: MeshUnit) {
        do {
            try workspace.applyManualEdit(edit, basedOn: model, distance: value, unit: unit)
            distance = ""
        } catch {
            workspace.modelError = error.localizedDescription
        }
    }
}
