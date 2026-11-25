import SwiftUI

struct DimensionControls: View {
    @ObservedObject var workspace: Workspace
    let model: WorkspaceModel
    @State private var dimension = ModelDimension.width
    @State private var inputUnit: MeshUnit
    @State private var length = ""

    init(workspace: Workspace, model: WorkspaceModel) {
        self.workspace = workspace
        self.model = model
        _inputUnit = State(initialValue: model.unit)
    }

    var body: some View {
        let span = model.extents[dimension.axis]
        let pin = model.pins.first { $0.dimension == dimension }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Dimension", selection: $dimension) {
                    ForEach(ModelDimension.allCases, id: \.self) { item in
                        Text(item.label).tag(item)
                    }
                }
                .fixedSize()
                Text("\(span.formatted(.number.precision(.significantDigits(1...15)))) \(model.unit.symbol)")
                Spacer()
                if let pin {
                    Label("\(pin.value.formatted(.number.precision(.significantDigits(1...15)))) \(pin.unit.symbol)", systemImage: "pin.fill")
                        .accessibilityLabel("Pinned at \(pin.value) \(pin.unit.symbol)")
                    Button("Unpin") { workspace.unpin(dimension) }
                } else {
                    Button("Pin Current") { workspace.pinCurrent(dimension) }
                }
            }
            HStack {
                TextField("Target length", text: $length)
                    .accessibilityLabel("Target length")
                    .frame(width: 120)
                Picker("Length unit", selection: $inputUnit) {
                    ForEach(MeshUnit.allCases, id: \.self) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Button("Set Once") { resize(changingPin: false) }
                    .disabled(length.isEmpty)
                if pin != nil {
                    Button("Change Pin") { resize(changingPin: true) }
                        .disabled(length.isEmpty)
                }
                Spacer()
                Text("±\(DimensionTarget.toleranceMM.formatted()) mm").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.bar)
        .onChange(of: dimension) { length = "" }
    }

    private func resize(changingPin: Bool) {
        let number = length.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
        guard let value = Double(number) else {
            workspace.modelError = "Enter a numeric length for \(dimension.label) in \(inputUnit.symbol)."
            return
        }
        let target = DimensionTarget(dimension: dimension, value: value, unit: inputUnit)
        if workspace.resize(to: target, changingPin: changingPin) { length = "" }
    }
}
